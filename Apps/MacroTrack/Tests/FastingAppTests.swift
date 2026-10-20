import Foundation
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// Fasts in the app: started from the last meal, ended by a meal (and back with its Undo) or by
/// hand, kept over a relaunch, gated over a day, notified, exported, and shown to the widgets.
@MainActor
struct FastingAppTests {
    /// Set up, meal timing on, and a banana eaten `hoursAgo`.
    func model(hoursAgo: Double = 3) throws -> (AppModel, TestEnvironment, FoodEntry) {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        model.setTracksMealTiming(true)
        let banana = try model.entry(foodID: Foods.bananaID, grams: 200, date: Date().addingTimeInterval(-hoursAgo * 3600))
        model.log([banana])
        return (model, environment, banana)
    }

    @Test func aFastStartsAtTheEndOfTheLastMeal() throws {
        let (model, _, banana) = try model()
        #expect(same(model.suggestedFastStart(), banana.date))
        model.startFast(goalHours: 16)
        let status = try #require(model.analysis?.fast)
        #expect(same(status.fast.start, banana.date) && status.fast.goalHours == 16)
        #expect(status.phase == .digesting)
        #expect(model.toast?.message.hasPrefix("Fasting from") == true)
    }

    @Test func aMealEndsTheFastAndItsUndoBringsItBack() throws {
        let (model, _, _) = try model()
        model.startFast(goalHours: 16)
        // Coffee doesn't break it.
        model.log([try model.entry(foodID: Foods.coffeeID, grams: 237)])
        #expect(model.analysis?.fast != nil)
        model.log([try model.entry(foodID: Foods.bananaID, grams: 150)])
        #expect(model.analysis?.fast == nil)
        #expect(model.toast?.message.contains("ended your") == true)
        let toast = try #require(model.toast)
        model.undo(toast)
        #expect(model.analysis?.fast != nil)
    }

    @Test func aStartBeforeTheLastMealIsMovedAfterIt() throws {
        let (model, _, banana) = try model()
        model.startFast(goalHours: 16, start: Date().addingTimeInterval(-5 * 3600))
        #expect(same(model.analysis?.fast?.fast.start, banana.date))
        model.updateFast(start: Date().addingTimeInterval(-6 * 3600))
        #expect(same(model.analysis?.fast?.fast.start, banana.date))
        model.updateFast(start: Date().addingTimeInterval(-3600))
        #expect(model.analysis?.fast != nil)
    }

    @Test func startingAndEndingAFastBothUndo() throws {
        let (model, _, _) = try model()
        model.startFast(goalHours: 16)
        model.undo(try #require(model.toast))
        #expect(model.analysis?.fast == nil && model.fasts.isEmpty)
        model.startFast(goalHours: 16)
        model.endFast()
        #expect(model.analysis?.fast == nil)
        model.undo(try #require(model.toast))
        #expect(model.analysis?.fast?.fast.goalHours == 16)
    }

    @Test func turningMealTimingOffEndsTheFast() throws {
        let (model, _, _) = try model()
        model.startFast(goalHours: 16)
        model.setTracksMealTiming(false)
        #expect(model.analysis?.fast == nil && model.pastFasts.count == 1)
    }

    @Test func endingByHandKeepsTheFastOverARelaunch() throws {
        let (model, environment, _) = try model(hoursAgo: 14)
        model.startFast(goalHours: 13)
        #expect(model.analysis?.fast?.goalReached == true)
        model.endFast()
        #expect(model.analysis?.fast == nil)
        let again = environment.model()
        #expect(again.pastFasts.count == 1)
        #expect(abs((again.pastFasts.first?.duration(at: Date()) ?? 0) - 14 * 3600) < 120)
        again.delete(fast: try #require(again.pastFasts.first?.id))
        #expect(again.pastFasts.isEmpty)
    }

    @Test func goalsOverADayAskOnceAndArentOfferedUnder18() throws {
        let (model, _, _) = try model()
        #expect(model.needsFastingScreen(goalHours: 36) && !model.needsFastingScreen(goalHours: 24))
        // Until the notes are read, nothing sets a goal past a day.
        model.startFast(goalHours: 36)
        #expect(model.analysis?.fast?.fast.goalHours == 24)
        model.acknowledgeFastingScreen()
        #expect(!model.needsFastingScreen(goalHours: 36))
        model.updateFast(goalHours: 36)
        #expect(model.analysis?.fast?.fast.goalHours == 36)
        #expect(model.fastingBlock == nil)
        var teen = SharedProfile.sample()
        teen.birthYear = model.today.year - 16
        model.save(profile: teen)
        #expect(model.fastingBlock == .under18)
        // One fast at a time: a start while one runs does nothing.
        #expect(!model.startFast(goalHours: 48))
        model.endFast()
        model.startFast(goalHours: 48)
        #expect(model.analysis?.fast?.fast.goalHours == 24)
    }

    @Test func notificationsAtEachPhaseToTheGoalWhileAlertsAreOn() throws {
        let (model, _, _) = try model()
        model.acknowledgeFastingScreen()
        model.startFast(goalHours: 36)
        let wanted = FastReminders.wanted(model)
        #expect(wanted.values.map(\.kind).sorted { $0.order < $1.order } == [.phase(.fatBurning), .phase(.ketosis), .goal])
        model.setFastAlerts(false)
        #expect(FastReminders.wanted(model).isEmpty)
        model.setFastAlerts(true)
        model.setTracksMealTiming(false)
        #expect(FastReminders.wanted(model).isEmpty)
    }

    @Test func theWidgetsSeeTheFastAndTheExportHasIt() throws {
        let (model, environment, banana) = try model()
        model.startFast(goalHours: 16)
        let snapshot = MacroSnapshot.load(from: environment.widgetURL)
        #expect(snapshot.tracksMealTiming == true && same(snapshot.fastStart, banana.date) && snapshot.fastGoalHours == 16)
        #expect(same(snapshot.lastMealEnd, banana.date))
        // And Lift Track's copy of the summary carries it.
        #expect(same(environment.shared.read(.nutrition)?.fast?.start, banana.date))
        model.endFast()
        let files = try model.exportCSV()
        #expect(files.contains { $0.lastPathComponent == "fasts.csv" })
        model.setTracksMealTiming(false)
        #expect(MacroSnapshot.load(from: environment.widgetURL).fastStart == nil)
    }

    @Test func aDaysGapsAreKeyedByTheMealAfterThemOnceItsComplete() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        let yesterday = model.today.adding(days: -1)
        let first = try model.entry(foodID: Foods.bananaID, grams: 200, date: yesterday.at(hour: 12, minute: 0))
        let second = try model.entry(foodID: Foods.bananaID, grams: 200, date: yesterday.at(hour: 13, minute: 20))
        model.log([first, second])
        model.setTracksMealTiming(true)
        // Not yet marked complete: the day's log isn't trusted, so it shows no gaps.
        #expect(model.gapsBefore(on: yesterday).isEmpty)
        model.setState(.complete, for: yesterday)
        let gaps = model.gapsBefore(on: yesterday)
        #expect(gaps[second.id]?.band == .close && gaps[first.id] == nil)
        // Off: none.
        model.setTracksMealTiming(false)
        #expect(model.gapsBefore(on: yesterday).isEmpty)
    }

    @Test func theFastLinkOpensTheFastScreenOnlyWithMealTimingOn() throws {
        let (model, _, _) = try model()
        DeepLink.open(URL(string: "macrotrack://fast")!, model: model)
        #expect(model.showFast)
        model.showFast = false
        model.setTracksMealTiming(false)
        DeepLink.open(URL(string: "macrotrack://fast")!, model: model)
        #expect(!model.showFast && model.tab == .today)
    }
}

/// The same moment to the millisecond, which is what the store keeps.
func same(_ a: Date?, _ b: Date) -> Bool {
    guard let a else { return false }
    return abs(a.timeIntervalSince(b)) < 0.001
}

extension FastMilestone.Kind {
    /// The order they come in, for comparing.
    var order: Int {
        switch self {
        case .phase(let phase): phase.rawValue
        case .goal: 100
        }
    }
}
