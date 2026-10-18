import Foundation
import SystemCore
import Testing

@testable import MacroTrack

/// macrotrack:// links from the widgets, controls and Shortcuts: each lands on its step, in place
/// of whatever sheet was up, on today at now.
@MainActor
struct DeepLinkTests {
    /// Each link's host and the logger it opens.
    nonisolated static let loggers: [(String, String)] = [
        ("log", "search"), ("search", "search"), ("scan", "scan"), ("camera", "camera"), ("photo", "camera"), ("describe", "describe"),
        ("quickadd", "quickAdd"),
    ]

    @Test(arguments: loggers)
    func aLinkOpensItsLogger(host: String, mode: String) throws {
        let model = TestEnvironment().model()
        model.onboard()
        DeepLink.open(try #require(URL(string: "macrotrack://\(host)")), model: model)
        #expect(model.logger == LogMode(rawValue: mode))
        #expect(model.logger != nil)
        #expect(model.loggerTime == nil, "a link logs now")
    }

    @Test func weighOpensTheWeighIn() throws {
        let model = TestEnvironment().model()
        model.onboard()
        DeepLink.open(try #require(URL(string: "macrotrack://weigh")), model: model)
        #expect(model.showWeighIn)
        #expect(model.logger == nil)
    }

    @Test func supplementsAndPlanOpenTheirScreens() throws {
        let model = TestEnvironment().model()
        model.onboard()
        DeepLink.open(try #require(URL(string: "macrotrack://supplements")), model: model)
        #expect(model.showSupplements)
        model.showSupplements = false
        DeepLink.open(try #require(URL(string: "macrotrack://plan")), model: model)
        #expect(model.tab == .plan)
        DeepLink.open(try #require(URL(string: "macrotrack://elsewhere")), model: model)
        #expect(model.tab == .today)
    }

    @Test func aLinkReplacesTheSheetThatsUp() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.showSettings = true
        model.selectedDay = model.today.adding(days: -2)
        model.openLogger(.describe, at: Date().addingTimeInterval(-3600))

        DeepLink.open(try #require(URL(string: "macrotrack://scan")), model: model)
        #expect(!model.showSettings)
        #expect(model.logger == .scan)
        #expect(model.loggerTime == nil)
        #expect(model.selectedDay == model.today, "a widget's tap is for today")

        DeepLink.open(try #require(URL(string: "macrotrack://weigh")), model: model)
        #expect(model.logger == nil, "only one sheet at a time")
        #expect(model.showWeighIn)
    }

    @Test func linksWaitForSetup() throws {
        let model = TestEnvironment().model()
        DeepLink.open(try #require(URL(string: "macrotrack://camera")), model: model)
        #expect(model.logger == nil)
        #expect(!model.showWeighIn)
    }
}

/// The widgets' snapshot: written only when it changes, read back as written, and fresh after midnight.
@MainActor
struct MacroSnapshotTests {
    @Test func roundTripsThroughItsFile() {
        let url = TestEnvironment().widgetURL
        var snapshot = MacroSnapshot(day: "2027-03-14", kcal: 1240, kcalTarget: 2300, protein: 96, proteinTarget: 170)
        snapshot.badge = "Day 5 of 21"
        snapshot.weighedToday = true
        #expect(snapshot.save(to: url))
        #expect(MacroSnapshot.load(from: url) == snapshot)
    }

    @Test func savesOnlyWhatChanged() {
        let url = TestEnvironment().widgetURL
        var snapshot = MacroSnapshot(day: "2027-03-14", kcal: 1240, kcalTarget: 2300)
        #expect(snapshot.save(to: url))
        // When it was written doesn't count as a change, so timelines aren't reloaded for nothing.
        snapshot.updated = snapshot.updated.addingTimeInterval(600)
        #expect(!snapshot.save(to: url))
        snapshot.kcal = 1500
        #expect(snapshot.save(to: url))
        #expect(!snapshot.save(to: nil), "no App Group, nothing written")
    }

    @Test func aNewDayStartsFromNothingEaten() {
        let snapshot = MacroSnapshot(
            day: Day(date(2027, 3, 14, 20), timeZone: .current).iso, kcal: 2100, kcalTarget: 2300, protein: 150,
            proteinTarget: 170, weighedToday: true)
        let sameDay = snapshot.current(now: date(2027, 3, 14, 23, 30, in: .current))
        #expect(sameDay == snapshot)

        let next = snapshot.current(now: date(2027, 3, 15, 0, 5, in: .current))
        #expect(next.day == "2027-03-15")
        #expect(next.kcal == 0 && next.protein == 0 && !next.weighedToday)
        #expect(next.kcalTarget == 2300, "the targets carry over until the app writes the new day's")
        #expect(next.kcalLeft == 2300)
    }

    @Test func theWidgetsDayIsTheAppsDay() {
        // The widgets compare this with the day the app wrote (`Day.iso`, Gregorian whatever the
        // phone's calendar: SystemCore's tests cover that), so the two must be the same string.
        let now = date(2027, 3, 14, 9, in: .current)
        #expect(MacroSnapshot.isoDay(now) == "2027-03-14")
        #expect(MacroSnapshot.isoDay(now) == Day(now).iso)
    }
}
