import FoodDatabase
import Foundation
import MealPlanner
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// The app model over an in-memory store and a temporary shared container: onboarding, the
/// sample data, logging and Undo, plans and check-ins, and what survives a relaunch.
@MainActor
struct AppModelTests {
    @Test func aFreshModelIsNotOnboarded() {
        let model = TestEnvironment().model()
        #expect(!model.onboarded)
        #expect(model.profile == nil)
        #expect(model.analysis == nil)
        #expect(model.entries.isEmpty)
        #expect(model.store.syncStatus == "Memory only")
    }

    @Test func onboardingSavesTheProfileSettingsAndFirstWeighIn() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard(history: .recentCut, weightKg: 82.4)

        #expect(model.onboarded)
        #expect(model.profile?.heightCm == 180)
        #expect(model.settings.dietHistory == .recentCut)
        #expect(model.settings.assessmentStart == model.today)
        #expect(model.settings.id == MacroSettings.singletonID)
        #expect(model.weighIns.map(\.kg) == [82.4])
        // Shared, so Lift Track and the Knowledge app don't ask again.
        #expect(environment.shared.read(.profile)?.goals == [.leaner])
        // The assessment starts: it asks for protein, not a calorie target.
        let analysis = try #require(model.analysis)
        #expect(analysis.targets.mode == .assessment)
        #expect(analysis.assessment?.complete == false)
        #expect(analysis.targets.protein != nil)
    }

    @Test func onboardingKeepsASetupThatAlreadySyncedIn() {
        // Set up on another device three weeks ago; its records arrive before this one finishes.
        let environment = TestEnvironment()
        let model = environment.model()
        let start = model.today.adding(days: -21)
        let earlier = SharedProfile.sample(updatedAt: start.date())
        environment.store.save(ProfileRecord(earlier))
        environment.store.save(
            MacroSettings(
                id: MacroSettings.singletonID, onboardedAt: start.date(), assessmentStart: start,
                dietHistory: .bulking, updatedAt: start.date()))

        var other = SharedProfile.sample()
        other.heightCm = 150
        model.completeOnboarding(profile: other, history: .none, weightKg: nil)

        #expect(model.onboarded)
        #expect(model.settings.assessmentStart == start, "the assessment isn't started again")
        #expect(model.settings.dietHistory == .bulking)
        #expect(model.profile?.heightCm == 180, "the synced profile isn't written over")
    }

    @Test func dataArrivingMidOnboardingFinishesIt() {
        // CloudKit brings the person's setup while onboarding is on screen: the store observer
        // calls reloadIfChanged, and the app leaves onboarding.
        let environment = TestEnvironment()
        let model = environment.model()
        #expect(!model.onboarded)
        environment.store.save(ProfileRecord(.sample()))
        environment.store.save(MacroSettings(id: MacroSettings.singletonID, onboardedAt: Date(), assessmentStart: model.today))
        #expect(!model.onboarded, "nothing read yet")
        model.reloadIfChanged()
        #expect(model.onboarded)
    }

    @Test func sampleDataGivesAnAnalysisAndAPlanToStart() throws {
        let model = TestEnvironment().model()
        SampleData.seedIfEmpty(model)

        #expect(model.onboarded)
        #expect(!model.entries.isEmpty)
        #expect(model.weighIns.count > 15)
        let analysis = try #require(model.analysis)
        #expect(analysis.assessment?.complete != false, "24 days covers the 21-day assessment")
        let recommendation = try #require(model.recommendation)
        #expect(!recommendation.phases.isEmpty)

        model.start(recommendation)
        #expect(model.plan != nil)
        #expect(model.recommendation == nil)
        #expect(model.analysis?.targets.kcal != nil, "a plan gives a calorie target")
        #expect(model.checkIns.map(\.id) == [CheckIn.id(for: model.today)])
    }

    @Test func theSupplementSampleTakesTwoWeeksOfDosesWithDrinksOn() {
        // -seedSupplements, as docs/macro-track.md describes it.
        let model = TestEnvironment().model()
        SampleData.seedIfEmpty(model)
        SampleData.seedSupplements(model)
        #expect(model.supplements.count == 4)
        #expect(model.tracksDrinks)
        #expect(model.entries(on: model.today).contains { $0.name == "Coffee" }, "this morning's coffee")
        let taken = Set(model.supplementLogs.map(\.day))
        #expect(taken.count > 10 && taken.allSatisfy { $0 < model.today }, "doses on most of the two weeks before today")
    }

    @Test func startingAnotherPlanTheSameDayReplacesTodaysCheckIn() throws {
        let model = TestEnvironment().model()
        SampleData.seedIfEmpty(model)
        let recommendation = try #require(model.recommendation)
        model.start(recommendation)
        let first = try #require(model.checkIns.last)

        let today = model.today
        let other = recommendation.phases.first?.kind == .leanBulk ? PhaseKind.cut : .leanBulk
        model.start(PhasePlan(phases: [PlannedPhase(kind: other, weeks: 8, start: today)], headline: "Mine", reasons: [], confidence: nil, arc: ""))

        let todays = model.checkIns.filter { $0.day == today }
        #expect(todays.count == 1, "one check-in a day, on every device")
        let second = try #require(model.checkIns.last)
        #expect(second.kcal != first.kcal)
        #expect(model.analysis?.targets.kcal == second.kcal, "the new plan's targets are the ones in force")
        #expect(model.plan?.phases.first?.kind == other)
    }

    @Test func checkInsOrderByDayThenByWhenTheyWereMade() {
        let day = Day(year: 2027, month: 3, day: 14)
        func checkIn(_ day: Day, _ kcal: Double, made hour: Int) -> CheckIn {
            CheckIn(
                day: day, expenditure: 2600, kcal: kcal, protein: 160, carbs: 220, fat: 70, status: .updated, reason: "",
                updatedAt: date(2027, 3, 14, hour))
        }
        let older = checkIn(day, 2200, made: 8)
        let newer = checkIn(day, 2400, made: 9)
        let weekBefore = checkIn(day.adding(days: -7), 2300, made: 10)
        // The last of a day is the one in force.
        #expect(AppModel.ordered([newer, weekBefore, older]).map(\.kcal) == [2300, 2200, 2400])
    }

    @Test func theSettingsSetUpFirstWin() {
        let first = MacroSettings(id: UUID(), onboardedAt: date(2027, 1, 1), dietHistory: .longCut, updatedAt: date(2027, 1, 1))
        let second = MacroSettings(id: MacroSettings.singletonID, onboardedAt: date(2027, 2, 1), dietHistory: .none, updatedAt: date(2027, 2, 2))
        let unfinished = MacroSettings(id: UUID(), updatedAt: date(2027, 3, 1))
        #expect(AppModel.inForce([second, unfinished, first])?.dietHistory == .longCut)
        #expect(AppModel.inForce([unfinished])?.id == unfinished.id)
        #expect(AppModel.inForce([]) == nil)
    }

    @Test func loggingAFoodChangesTodayAndSurvivesARelaunch() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        let before = try #require(model.analysis).todayIntake.kcal

        let banana = try model.entry(foodID: Foods.bananaID, grams: 120)
        model.log([banana])

        let after = try #require(model.analysis).todayIntake
        #expect(abs(after.kcal - before - 106.8) < 0.5)
        #expect(abs(after.protein - 1.308) < 0.01)
        #expect(model.toast?.message == "Logged Bananas, raw · 107 kcal")
        #expect(model.toast?.undo == [banana.id])
        #expect(banana.day == model.today)
        #expect(banana.unitID == "g")

        // Another launch over the same store reads it back.
        let relaunched = environment.model()
        #expect(relaunched.entries.map(\.id) == [banana.id])
        #expect(relaunched.entries.first?.grams == 120)
        #expect(abs((relaunched.analysis?.todayIntake.kcal ?? 0) - after.kcal) < 0.01)
    }

    @Test func undoTakesBackWhatWasJustLogged() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.log([try model.entry(foodID: Foods.bananaID, grams: 120), try model.entry(foodID: Foods.bananaID, grams: 60)])
        let toast = try #require(model.toast)
        #expect(toast.message.hasPrefix("Logged 2 foods"))

        model.undo(toast)
        #expect(model.entries.isEmpty)
        #expect(model.analysis?.todayIntake.kcal == 0)
        #expect(model.store.all(FoodEntry.self).isEmpty)
    }

    @Test func undoingADeleteBringsTheEntriesBack() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let entries = [try model.entry(foodID: Foods.bananaID, grams: 120), try model.entry(foodID: Foods.coffeeID, grams: 237)]
        model.log(entries)

        model.delete(entries: entries.map(\.id))
        #expect(model.entries.isEmpty)
        let toast = try #require(model.toast)
        #expect(toast.message == "Deleted 2 foods")

        model.undo(toast)
        #expect(Set(model.entries.map(\.id)) == Set(entries.map(\.id)))
        #expect(model.toast == nil)
    }

    @Test func quickAddLogsCaloriesAndProtein() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.quickAdd(name: "", nutrients: Nutrients(kcal: 650, protein: 40, carbs: 0, fat: 0))
        let entry = try #require(model.entries.last)
        #expect(entry.name == "Quick add")
        #expect(entry.source == .quickAdd)
        #expect(model.analysis?.todayIntake.kcal == 650)
        #expect(model.toast?.message == "Logged Quick add · 650 kcal")
    }

    @Test func aTimePickedInTheLoggerLastsOnlyWhileItsOpen() {
        let model = TestEnvironment().model()
        model.onboard()
        let earlier = Date().addingTimeInterval(-2 * 3600)
        model.openLogger(.search, at: earlier)
        #expect(model.logger == .search)
        #expect(model.logDate() == earlier)

        // The day changes (catching up yesterday): the picked time goes.
        model.selectedDay = model.today.adding(days: -1)
        #expect(model.loggerTime == nil)
        let caughtUp = model.logDate()
        #expect(Day(caughtUp) == model.today.adding(days: -1), "a past day logs to that day")
        let now = Date()
        let clock = Calendar.gregorian(.current)
        #expect(clock.component(.hour, from: caughtUp) == clock.component(.hour, from: now) || abs(now.timeIntervalSince(caughtUp) - 86_400) < 3_700)

        model.selectedDay = model.today
        #expect(abs(model.logDate().timeIntervalSinceNow) < 2, "today logs now")
    }

    @Test func aPastDaysTimeComesFromThatDay() {
        let model = TestEnvironment().model()
        model.onboard()
        model.selectedDay = model.today.adding(days: -3)
        let picked = model.onSelectedDay(date(2027, 3, 14, 13, 45, in: .current))
        #expect(Day(picked) == model.today.adding(days: -3))
        let clock = Calendar.gregorian(.current).dateComponents([.hour, .minute], from: picked)
        #expect(clock.hour == 13 && clock.minute == 45)
    }

    @Test func aWeighInIsSavedAndCanBeIgnored() throws {
        let model = TestEnvironment().model()
        model.onboard(weightKg: nil)
        model.weighIn(kg: 81.3)
        #expect(model.toast?.message == "Weighed in · 81.3 kg")
        let weighIn = try #require(model.latestWeighIn)
        #expect(weighIn.kg == 81.3)

        model.setExcluded(true, weighIn: weighIn)
        #expect(model.latestWeighIn == nil)
        #expect(model.weighIns.first?.excluded == true)

        model.delete(weighIn: try #require(model.weighIns.first))
        #expect(model.weighIns.isEmpty)
    }

    @Test func aDaysStateCanBeSetAndCleared() {
        let model = TestEnvironment().model()
        model.onboard()
        model.setState(.complete, for: model.today)
        #expect(model.state(of: model.today) == .complete)
        model.setState(.partial, for: model.today)
        #expect(model.state(of: model.today) == .partial)
        #expect(model.dayStatus.count == 1)
        model.setState(nil, for: model.today)
        #expect(model.state(of: model.today) == nil)
    }

    @Test func aCorrectedLabelUpdatesTheSameFood() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let label = Food(
            id: "label", name: "Granola", barcode: "00012345678905", basis: .g,
            nutrients: Nutrients(kcal: 450, protein: 10, carbs: 60, fat: 18), source: .label)
        let saved = model.save(customFood: label)
        var corrected = label
        corrected.name = "Granola, maple"
        let id = try #require(CustomFoodRecord.recordID(fromFoodID: saved.id))
        let resaved = model.save(customFood: corrected, replacing: id)

        #expect(resaved.id == saved.id)
        #expect(model.customFoods.count == 1)
        #expect(model.food(barcode: "00012345678905")?.name == "Granola, maple")
        #expect(model.food(id: saved.id)?.name == "Granola, maple")
        #expect(CustomFoodRecord.recordID(fromFoodID: "usda:173944") == nil)
    }

    @Test func aFavoriteTogglesOnAndOff() {
        let model = TestEnvironment().model()
        model.onboard()
        model.toggleFavorite(Foods.bananaID)
        #expect(model.isFavorite(Foods.bananaID))
        model.toggleFavorite(Foods.bananaID)
        #expect(!model.isFavorite(Foods.bananaID))
    }

    @Test func aSettingsChangeKeepsOneThatSyncedInMeanwhile() {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        // Another device turned drinks on; the import hasn't been read yet. Its clock runs a
        // little ahead of this one's.
        var synced = environment.store.all(MacroSettings.self)[0]
        synced.tracksDrinks = true
        synced.updatedAt = Date().addingTimeInterval(2)
        environment.store.save(synced)

        model.updateSettings { $0.showAllMacros = false }
        #expect(model.settings.showAllMacros == false, "an edit is newer than what it edits, whatever the clocks say")
        #expect(model.settings.tracksDrinks == true, "the edit is made to the settings as stored")
    }

    @Test func aCutBackStepsDownWithoutTouchingTheLimit() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.updateSettings { $0.caffeineLimit = 350 }
        model.startCutBack(from: 400, goal: 200)
        let cut = try #require(model.settings.caffeineCutBack)
        #expect(cut.start == model.today)
        #expect(model.settings.caffeineLimit == 350, "the report takes the lower of the limit and the week's step")

        // Stopped before the goal: the limit is what it was.
        model.endCutBack()
        #expect(model.settings.caffeineCutBack == nil)
        #expect(model.settings.caffeineLimit == 350)

        // Stopped after reaching it: the goal stays as the limit.
        let start = model.today.adding(weeks: -10)
        model.updateSettings { $0.caffeineCutBack = CaffeineCutBack(start: start, from: 400, goal: 200) }
        model.endCutBack()
        #expect(model.settings.caffeineLimit == 200)
    }

    @Test func aStandardDrinkLogsItsUsualSize() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let coffee = try #require(QuickDrink.standard.first { $0.id == "coffee" })
        model.log(coffee)
        let entry = try #require(model.entries.last)
        #expect(entry.name == "Coffee")
        #expect(entry.source == .drink)
        #expect(abs((entry.grams ?? 0) - 237) < 1)
        #expect(abs((entry.fluid ?? 0) - 237) < 1)
        #expect((entry.micros?["caffeine"] ?? 0) > 50, "USDA lists brewed coffee's caffeine")
    }

    @Test func waterIsLoggedWithUndo() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.addWater(ml: 500)
        #expect(model.water.map(\.ml) == [500])
        let toast = try #require(model.toast)
        #expect(toast.undoWater.count == 1)
        model.undo(toast)
        #expect(model.water.isEmpty)
    }

    @Test func aMealPlanForTheSameStartReplacesTheOneNotStarted() {
        let model = TestEnvironment().model()
        SampleData.seedIfEmpty(model)
        let monday = model.planStart(tomorrow: false)
        #expect(monday.weekday == .monday)
        #expect((1...7).contains(model.today.days(until: monday)))
        #expect(model.planStart(tomorrow: true) == model.today.adding(days: 1))

        let preferences = PlanPreferences(slots: [.lunch, .dinner])
        let first = model.makeMealPlan(preferences: preferences, start: monday)
        let second = model.makeMealPlan(preferences: preferences, start: monday)
        #expect(second.id == first.id, "a screen showing the week shows the new one")
        #expect(model.mealPlans.count == 1)
        #expect(model.mealPlan?.id == first.id)
    }

    @Test func aMealPlanBeingEatenFromIsKeptWhenTheNextIsMade() {
        let model = TestEnvironment().model()
        SampleData.seedIfEmpty(model)
        let current = model.makeMealPlan(preferences: PlanPreferences(slots: [.dinner]), start: model.today.adding(days: -1))
        let next = model.makeMealPlan(preferences: PlanPreferences(slots: [.dinner]), start: current.end.adding(days: 1))
        #expect(Set(model.mealPlans.map(\.id)) == [current.id, next.id])
        #expect(model.mealPlan(covering: model.today)?.id == current.id)
    }

    @Test func otherDishesKeepTheDaysEatenAndTheMealsLogged() throws {
        let model = TestEnvironment().model()
        SampleData.seedIfEmpty(model)
        let plan = model.makeMealPlan(preferences: PlanPreferences(slots: Set(MealSlot.allCases)), start: model.today.adding(days: -1))
        let lunch = try #require(plan.meals.first { $0.day == model.today && $0.slot == .lunch })
        model.logPlanned(lunch, in: plan)
        let logged = try #require(model.mealPlans.first { $0.id == plan.id })
        let eaten = logged.meals.filter { $0.day < model.today } + [lunch]
        let before = Set(model.swappableRecipes(in: logged))
        #expect(!before.isEmpty)

        model.shuffleMealPlan(logged)
        let shuffled = try #require(model.mealPlans.first { $0.id == plan.id }, "the same plan, so a screen showing it shows the new dishes")
        #expect(model.mealPlans.count == 1)
        #expect(eaten.allSatisfy(shuffled.meals.contains), "yesterday and the lunch logged today, as they were")
        #expect(model.isLogged(lunch, in: shuffled))
        let upcoming = shuffled.meals.filter { $0.day >= model.today && shuffled.logged[$0.id] == nil }
        #expect(!upcoming.isEmpty)
        #expect(upcoming.allSatisfy { !before.contains($0.recipeID) }, "every dish still to come is another")

        // Again: another set again, not the first one back.
        model.shuffleMealPlan(shuffled)
        let again = try #require(model.mealPlans.first { $0.id == plan.id })
        #expect(again.meals.filter { $0.day >= model.today && again.logged[$0.id] == nil }.map(\.recipeID) != upcoming.map(\.recipeID))
        #expect(eaten.allSatisfy(again.meals.contains))
    }

    @Test func aWeekThatsOverHasNoOtherDishes() throws {
        let model = TestEnvironment().model()
        SampleData.seedIfEmpty(model)
        let made = model.makeMealPlan(preferences: PlanPreferences(slots: [.dinner]), start: model.today.adding(days: -9))
        let past = try #require(model.mealPlans.first { $0.id == made.id })
        #expect(model.swappableRecipes(in: past).isEmpty)
        model.shuffleMealPlan(past)
        #expect(model.mealPlans.first { $0.id == past.id } == past, "left as it was, not even saved again")
    }

    @Test func aPlannedMealLogsTodayAtNowEvenAfterAPickedTime() throws {
        let model = TestEnvironment().model()
        SampleData.seedIfEmpty(model)
        let plan = model.makeMealPlan(preferences: PlanPreferences(slots: Set(MealSlot.allCases)), start: model.today.adding(days: -1))
        let meal = try #require(plan.meals.first { $0.day == model.today })

        // "+" on a moment two hours ago, then the logger closed: closing it drops the time.
        model.openLogger(.search, at: Date().addingTimeInterval(-7200))
        model.logger = nil
        #expect(model.loggerTime == nil)

        let logging = Date()
        model.logPlanned(meal, in: plan)
        let logged = Date()
        let entry = try #require(model.entries.last)
        #expect(entry.source == .plan)
        #expect(entry.date > logging.addingTimeInterval(-1) && entry.date < logged.addingTimeInterval(1), "now, not two hours ago")
        #expect(entry.day == model.today)
        let saved = try #require(model.mealPlans.first { $0.id == plan.id })
        #expect(model.isLogged(meal, in: saved))
    }
}
