import Foundation
import NutritionEngine
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

    @Test func comingToTheFrontWithoutHavingLeftDoesNothing() {
        let model = model()
        model.show(day: yesterdayIn(model))
        model.cameToFront()
        #expect(model.selectedDay == yesterdayIn(model))
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
        model.showDoses(on: model.today)
        #expect(model.tab == .today)
        #expect(model.pendingSupplementsScroll, "Today may not exist yet: it takes this up when it does")
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
