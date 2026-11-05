import Foundation
import NutritionEngine
import SwiftUI
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// Which day and tab the app is on: one day, kept by the Log tab and Foods, and let go of anywhere
/// else, so a food never lands on a day nobody's looking at.
@MainActor
struct LogTabTests {
    func model() -> AppModel {
        let model = TestEnvironment().model()
        model.onboard()
        return model
    }

    var yesterdayIn: (AppModel) -> Day { { $0.today.adding(days: -1) } }

    @Test func leavingTheLogGoesBackToToday() {
        let model = model()
        model.show(day: yesterdayIn(model))
        #expect(model.tab == .log)
        #expect(model.selectedDay == yesterdayIn(model))

        model.tab = .plan

        #expect(model.selectedDay == model.today)
    }

    @Test func leavingFoodsGoesBackToTodayToo() {
        let model = model()
        model.tab = .foods
        model.selectedDay = yesterdayIn(model)
        model.tab = .today
        #expect(model.selectedDay == model.today)
    }

    @Test func betweenTheLogAndFoodsTheDayStays() {
        let model = model()
        model.show(day: yesterdayIn(model))
        model.tab = .foods
        #expect(model.selectedDay == yesterdayIn(model))
        model.tab = .log
        #expect(model.selectedDay == yesterdayIn(model))
    }

    @Test func aWhileAwayComesBackToToday() {
        let model = model()
        model.show(day: yesterdayIn(model))
        let anchors = model.logAnchorRequest
        let left = Date()

        model.wentToBackground(at: left)
        model.cameToFront(at: left.addingTimeInterval(AppModel.awayLimit))

        #expect(model.selectedDay == model.today)
        #expect(model.logAnchorRequest == anchors + 1)
    }

    @Test func aGlanceAwayStaysPut() {
        let model = model()
        model.show(day: yesterdayIn(model))
        let left = Date()
        model.wentToBackground(at: left)
        model.cameToFront(at: left.addingTimeInterval(AppModel.awayLimit - 1))
        #expect(model.selectedDay == yesterdayIn(model))
    }

    @Test func aLoggerLeftOpenKeepsItsDay() {
        let model = model()
        model.show(day: yesterdayIn(model))
        model.openLogger(.quickAdd)
        let left = Date()
        model.wentToBackground(at: left)
        model.cameToFront(at: left.addingTimeInterval(AppModel.awayLimit * 2))
        #expect(model.selectedDay == yesterdayIn(model))
    }

    /// The Mac says so twice when it's behind another app and then gets hidden: the time away runs
    /// from the first.
    @Test func aWhileAwayRunsFromTheFirstSignOfLeaving() {
        let model = model()
        model.show(day: yesterdayIn(model))
        let left = Date(timeIntervalSinceReferenceDate: 800_000_000)

        model.wentToBackground(at: left)
        model.wentToBackground(at: left.addingTimeInterval(AppModel.awayLimit - 1))
        model.cameToFront(at: left.addingTimeInterval(AppModel.awayLimit))

        #expect(model.selectedDay == model.today)
    }

    /// Coming back says so twice too, on the Mac: the second is for the same return, not a new one.
    @Test func comingBackOnceMovesTheDayOnce() {
        let model = model()
        model.show(day: yesterdayIn(model))
        let left = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let back = left.addingTimeInterval(AppModel.awayLimit)
        model.wentToBackground(at: left)
        model.cameToFront(at: back)
        let anchors = model.logAnchorRequest

        model.show(day: yesterdayIn(model))
        model.cameToFront(at: back)

        #expect(model.selectedDay == yesterdayIn(model))
        #expect(model.logAnchorRequest == anchors)
    }

    @Test func comingToTheFrontWithoutHavingLeftDoesNothing() {
        let model = model()
        model.show(day: yesterdayIn(model))
        model.cameToFront()
        #expect(model.selectedDay == yesterdayIn(model))
    }

    /// What a past day's foot takes goes on that day, and leaves today alone.
    @Test func aPastDaysDosesAndWaterGoOnThatDay() throws {
        let model = model()
        let yesterday = yesterdayIn(model)
        let facts = SupplementFacts(
            id: "custom:Multi", name: "Multi", unit: "tablet", ingredients: [SupplementIngredient(name: "Zinc", amount: 11, unit: "mg")],
            source: .custom)
        model.store.save(Supplement(facts: facts, doses: [Dose(time: .morning, count: 1)]))
        model.reload()
        model.show(day: yesterday)

        model.take(model.doses(on: yesterday), on: yesterday)
        model.addWater(ml: 250)
        model.setState(.partial, for: yesterday)

        #expect(model.doses(on: yesterday).map(\.taken) == [true])
        #expect(model.doses(on: model.today).map(\.taken) == [false])
        #expect(Day(try #require(model.water.last).date) == yesterday)
        #expect(model.state(of: yesterday) == .partial)
        #expect(model.state(of: model.today) == nil)
    }

    /// Chips hold still once they're there: a food logged doesn't move the next one out from under
    /// a thumb, whatever happens to the row meanwhile. Going away is where they're taken again.
    @Test func logAgainsOrderHoldsUntilTheNextVisit() throws {
        let model = model()
        let day = yesterdayIn(model)
        func food(_ name: String, kcal: Double) -> FoodEntry {
            FoodEntry(
                date: day.at(hour: 8, minute: 0), name: name, amountLabel: "1", nutrients: Nutrients(kcal: kcal, protein: 1, carbs: 1, fat: 1),
                source: .search)
        }
        model.log([food("Oats", kcal: 300), food("Yogurt", kcal: 120)])
        let before = model.logAgainChips.map(\.template.name)
        #expect(Set(before) == ["Oats", "Yogurt"], "it fills itself with nothing there yet")
        let last = try #require(before.last)

        // The lower chip, tapped again and again, climbs the ranking but not the row.
        for _ in 0..<6 { model.logAgain(try #require(model.logAgainChips.first { $0.template.name == last })) }
        #expect(model.logAgain.first?.template.name == last)
        #expect(model.logAgainChips.map(\.template.name) == before)

        // As on the Mac, where switching apps never reaches the scene phase's background.
        model.wentToBackground()
        #expect(model.logAgainChips.first?.template.name == last)
    }

    @Test func logAgainsOrderIsTakenOnChangingTab() throws {
        let model = model()
        let day = yesterdayIn(model)
        func food(_ name: String, kcal: Double) -> FoodEntry {
            FoodEntry(
                date: day.at(hour: 8, minute: 0), name: name, amountLabel: "1", nutrients: Nutrients(kcal: kcal, protein: 1, carbs: 1, fat: 1),
                source: .search)
        }
        model.log([food("Oats", kcal: 300), food("Yogurt", kcal: 120)])
        let last = try #require(model.logAgainChips.last)
        for _ in 0..<6 { model.logAgain(last) }

        model.tab = .log
        #expect(model.logAgainChips.first?.template.name == last.template.name)
    }

    @Test func theColumnsNeedRoomAndOrdinaryText() {
        #expect(LogColumns.fit(width: 600, textSize: .large))
        #expect(LogColumns.fit(width: 600, textSize: .xxxLarge), "these still fit, scaled")
        #expect(!LogColumns.fit(width: 519, textSize: .large), "beside a pane in the smallest window")
        #expect(!LogColumns.fit(width: 900, textSize: .accessibility1), "no scale factor saves these")
    }

    @Test func theLastTabComesBackOnTheNextLaunch() throws {
        let defaults = try #require(UserDefaults(suiteName: "LogTabTests-\(UUID().uuidString)"))
        let environment = TestEnvironment()
        func launched() -> AppModel {
            AppModel(
                store: environment.store, shared: environment.shared, widgetURL: environment.widgetURL, defaults: defaults, catalog: Catalogs.food,
                supplementCatalog: nil)
        }
        let first = launched()
        first.onboard()
        #expect(first.tab == .today)
        first.tab = .log

        #expect(launched().tab == .log)
    }

    @Test func aLinkGoesToTodayWhateverTheLogShows() throws {
        let model = model()
        model.show(day: yesterdayIn(model))
        DeepLink.open(try #require(URL(string: "macrotrack://quickadd")), model: model)
        #expect(model.selectedDay == model.today)
        #expect(model.logger == .quickAdd)
    }

    @Test func aNarrowWindowFallsBackToWhatTheTabBarHas() {
        #expect(AppTab.foods.compactFallback == .log)
        #expect(AppTab.mealPlan.compactFallback == .plan)
        #expect(AppTab.history.compactFallback == .progress)
        #expect(AppTab.supplements.compactFallback == .today)
        #expect(AppTab.log.compactFallback == .log)
        #expect(!AppTab.log.isSidebarOnly)
    }

    @Test func aReminderWaitsForTodayToBeThere() {
        let model = model()
        model.tab = .log
        model.showDoses()
        #expect(model.tab == .today)
        #expect(model.pendingSupplementsScroll, "Today may not exist yet: it takes this up when it does")
    }

    /// Monday's reminder, tapped on Tuesday with the app already on Today: the tab doesn't change, so
    /// nothing else brings the day back, and a Log again chip would land on Monday.
    @Test func aReminderFromAnEarlierDayLeavesNoDayBehindToday() throws {
        let model = model()
        model.tab = .today
        model.selectedDay = yesterdayIn(model)

        model.showDoses()

        #expect(model.tab == .today)
        #expect(model.selectedDay == model.today)
        #expect(Day(model.logDate()) == model.today)
    }

    @Test func theMenusKeepToTheirOrder() {
        #expect(AppTab.allCases.firstIndex(of: .log) == 1, "⌘2")
        #expect(AppTab.allCases.firstIndex(of: .foods) == 2, "⌘3")
        #expect(AppTab.allCases.firstIndex(of: .history) == 7, "⌘8")
    }

    @Test func theBarNamesItsDay() {
        let model = model()
        #expect(model.logTargetTitle == "Log food")
        model.show(day: yesterdayIn(model))
        #expect(model.logTargetTitle.hasPrefix("Log to "))
    }

    /// Just after midnight a time picked last night is on another day than the one selected, and
    /// that's the day the food goes on.
    @Test func quickAddNamesTheDayItsFoodLandsOn() {
        let model = model()
        #expect(model.quickAddNote.contains("toward today"))

        let lastNight = yesterdayIn(model).at(hour: 23, minute: 30)
        model.openLogger(.quickAdd, at: lastNight)
        #expect(model.selectedDay == model.today)
        #expect(model.quickAddNote.contains("toward yesterday"))

        model.quickAdd(name: "Toast", nutrients: Nutrients(kcal: 200, protein: 8, carbs: 30, fat: 4))
        #expect(model.allEntries(on: yesterdayIn(model)).map(\.name).contains("Toast"))
    }

    @Test func quickAddNamesASelectedDayToo() {
        let model = model()
        model.show(day: yesterdayIn(model))
        #expect(model.quickAddNote.contains("toward yesterday"))
        let earlier = model.today.adding(days: -3)
        model.selectedDay = earlier
        #expect(model.quickAddNote.contains("toward \(Format.day(earlier))"))
    }

    @Test func aDaysTargetsAreThoseOfThatDay() throws {
        let model = model()
        let plan = try #require(model.recommendation)
        model.start(plan)
        #expect(model.targets(on: model.today)?.kcal == model.analysis?.targets.kcal)
        // Long before the plan began: only protein.
        let old = model.today.adding(days: -200)
        #expect(model.targets(on: old)?.kcal == nil)
        #expect(model.targets(on: old)?.protein != nil)
    }
}
