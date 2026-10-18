import FoodDatabase
import Foundation
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack

/// Today's one-tap foods for a short nutrient and for fermented foods: an ordinary portion that
/// covers enough, under 300 kcal, the person's own foods first. Over an empty catalog, so only the
/// person's foods are in play.
struct FoodFixTests {
    let empty = FoodCatalog(usda: nil, off: nil)
    let potassium = Micronutrients.info("potassium")

    static let potato = Food(
        id: "custom:potato", name: "Baked potato", basis: .g, nutrients: Nutrients(kcal: 93, protein: 2.5, carbs: 21, fat: 0.1),
        extras: ["potassium": 535], portions: [Portion(label: "1 medium", amount: 173)], source: .custom, processing: .whole)
    static let banana = Food(
        id: "custom:banana", name: "Banana", basis: .g, nutrients: Nutrients(kcal: 89, protein: 1.1, carbs: 22.8, fat: 0.3),
        extras: ["potassium": 358], portions: [Portion(label: "1 medium", amount: 118)], source: .custom, processing: .whole)
    /// Sold by the tub: the usual portion is 700 kcal.
    static let potatoSalad = Food(
        id: "custom:salad", name: "Potato salad", basis: .g, nutrients: Nutrients(kcal: 140, protein: 3, carbs: 15, fat: 7.5),
        extras: ["potassium": 600], portions: [Portion(label: "1 tub", amount: 500)], source: .custom, processing: .processed)

    @Test func theFoodThatCoversASixthOfTheTargetWins() throws {
        let nutrient = try #require(potassium)
        let personal = [PersonalFood(food: Self.banana, score: 5), PersonalFood(food: Self.potato, score: 1)]
        let fix = try #require(MicroFix.find(for: nutrient, target: 3400, personal: personal, catalog: empty))
        // A medium banana has 422 mg, under a sixth of 3,400: it can't be the fix however often it's eaten.
        #expect(fix.food.id == Self.potato.id)
        #expect(fix.yours)
        #expect(fix.amount >= 3400 / 6)
        #expect(fix.kcal <= 300)
    }

    @Test func aWholeTubIsntAPortion() throws {
        let nutrient = try #require(potassium)
        let fix = try #require(MicroFix.find(for: nutrient, target: 3400, personal: [PersonalFood(food: Self.potatoSalad, score: 1)], catalog: empty))
        // 500 g is 700 kcal: the portion nearest a snack's 150 kcal instead.
        #expect(fix.unit.id == "g")
        #expect(fix.count == 100)
        #expect(fix.kcal == 140)
    }

    @Test func nothingEatenCoversIt() throws {
        let nutrient = try #require(potassium)
        #expect(MicroFix.find(for: nutrient, target: 3400, personal: [PersonalFood(food: Self.banana, score: 1)], catalog: empty) == nil)
    }

    @Test func aFermentedFoodTheyEatComesFirstUnlessUltraProcessed() throws {
        let kefir = Food(
            id: "custom:kefir", name: "Kefir", basis: .g, nutrients: Nutrients(kcal: 63, protein: 3.6, carbs: 4.5, fat: 3.3),
            portions: [Portion(label: "1 cup", amount: 243)], source: .custom, processing: .whole, fermented: true)
        let sweet = Food(
            id: "custom:yogurt", name: "Strawberry yogurt drink", basis: .g, nutrients: Nutrients(kcal: 90, protein: 3, carbs: 15, fat: 2),
            portions: [Portion(label: "1 bottle", amount: 200)], source: .custom, processing: .ultraProcessed, fermented: true)
        let fix = try #require(
            FermentedFix.find(personal: [PersonalFood(food: sweet, score: 9), PersonalFood(food: kefir, score: 1)], catalog: empty))
        #expect(fix.food.id == kefir.id)
        #expect(fix.yours)
        #expect(fix.kcal <= 300)
    }

    @Test func aQuartOfKefirComesDownToAGlass() throws {
        let quart = Food(
            id: "custom:kefir-quart", name: "Kefir", basis: .g, nutrients: Nutrients(kcal: 63, protein: 3.6, carbs: 4.5, fat: 3.3),
            portions: [Portion(label: "1 quart", amount: 976)], source: .custom, processing: .whole, fermented: true)
        let fix = try #require(FermentedFix.make(quart, lastUnitID: nil, lastCount: nil, lastAmount: nil, yours: true))
        #expect(fix.unit.id == "g")
        #expect(fix.count == 150)
    }
}

/// Supplement reminders: a time of day with doses still open, from now on, for three days.
@MainActor
struct SupplementReminderTests {
    func modelWithAStack() -> (AppModel, Supplement) {
        let model = TestEnvironment().model()
        model.onboard()
        let facts = SupplementFacts(
            id: "custom:fish-oil", name: "Fish oil", servingCount: 1, unit: "softgel",
            ingredients: [SupplementIngredient(name: "EPA", amount: 216, unit: "mg")], source: .custom)
        let fish = Supplement(facts: facts, doses: [Dose(time: .morning, count: 2), Dose(time: .evening, count: 1)])
        model.save(supplement: fish)
        model.updateSettings {
            $0.supplementReminders = true
            $0.doseTimes = [.morning: 8 * 60, .evening: 20 * 60]
        }
        return (model, fish)
    }

    @Test func eachOpenTimeForThreeDaysGetsOne() throws {
        let (model, _) = modelWithAStack()
        let wanted = SupplementReminders.wanted(model, now: model.today.date())
        #expect(wanted.count == 6)
        let morning = try #require(wanted["dose-\(model.today.iso)-morning"])
        #expect(morning.date == model.today.at(minutes: 8 * 60))
        #expect(morning.body.contains("Fish oil"))
        #expect(wanted["dose-\(model.today.adding(days: 2).iso)-evening"] != nil)
    }

    @Test func aTakenDoseAndAPastTimeLoseTheirs() {
        let (model, _) = modelWithAStack()
        _ = model.takeAll(at: .morning, on: model.today)
        let wanted = SupplementReminders.wanted(model, now: model.today.date())
        #expect(wanted["dose-\(model.today.iso)-morning"] == nil)
        #expect(wanted.count == 5)

        // Late in the evening, today's are behind.
        let late = SupplementReminders.wanted(model, now: model.today.at(hour: 21, minute: 0))
        #expect(late.keys.allSatisfy { !$0.contains(model.today.iso) })
        #expect(late.count == 4)
    }

    @Test func remindersOffWantsNone() {
        let (model, _) = modelWithAStack()
        model.updateSettings { $0.supplementReminders = false }
        #expect(SupplementReminders.wanted(model, now: model.today.date()).isEmpty)
    }

    @Test func takingAllATimesDosesShowsUndo() throws {
        let (model, _) = modelWithAStack()
        #expect(model.takeAll(at: .morning, on: model.today) == 1)
        #expect(model.doses(on: model.today).filter { $0.dose.time == .morning }.allSatisfy { $0.taken })
        // Nothing left to take there.
        #expect(model.takeAll(at: .morning, on: model.today) == 0)
        let evening = try #require(model.doses(on: model.today).first { $0.dose.time == .evening })
        model.skip(evening, on: model.today)
        #expect(model.doses(on: model.today).first { $0.dose.time == .evening }?.skipped == true)
        // Taking a skipped dose replaces the skip.
        model.take(model.doses(on: model.today).filter { $0.dose.time == .evening }, on: model.today, message: "Took it")
        #expect(model.doses(on: model.today).allSatisfy { $0.taken })
        let toast = try #require(model.toast)
        model.undo(toast)
        #expect(model.doses(on: model.today).first { $0.dose.time == .evening }?.open == true)
    }
}

/// What Siri and Shortcuts say and log, with the model in whatever state the app left it.
@MainActor
struct IntentTests {
    @Test func theRemainingSentenceSaysWhatsLeft() throws {
        let model = TestEnvironment().model()
        #expect(model.remainingSentence == "", "nothing before setup")
        SampleData.seedIfEmpty(model)
        model.start(try #require(model.recommendation))
        let sentence = model.remainingSentence
        #expect(sentence.hasSuffix(" today."))
        #expect(sentence.first?.isUppercase == true || sentence.first?.isNumber == true)

        model.quickAdd(name: "Feast", nutrients: Nutrients(kcal: 9000, protein: 400, carbs: 0, fat: 0))
        #expect(model.remainingSentence.contains("kcal over"))
        #expect(!model.remainingSentence.contains("protein to go"))
    }

    @Test func aDescriptionWithoutTheModelLogsTheBestMatch() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        #expect(!model.ai.canDescribe, "tests never configure Apple's model")
        let asked = Date()
        let reply = await model.logDescribed("banana")
        let answered = Date()
        #expect(reply.hasPrefix("Logged "))
        let entry = try #require(model.entries.last)
        #expect(entry.source == .shortcut)
        // Eaten when asked, however long the search took: a busy machine can make that seconds. (A
        // second either side for the store's millisecond dates.)
        #expect(entry.date > asked.addingTimeInterval(-1) && entry.date < answered.addingTimeInterval(1))
        #expect(entry.nutrients.kcal > 0)
    }

    @Test func aStaleDayIsCaughtUpBeforeAnIntentRuns() {
        let model = TestEnvironment().model()
        model.onboard()
        // As if the app was last active yesterday and Siri woke it after midnight.
        model.today = model.today.adding(days: -1)
        model.selectedDay = model.today
        model.refreshDay()
        #expect(model.today == .today)
        #expect(model.selectedDay == .today)
    }
}
