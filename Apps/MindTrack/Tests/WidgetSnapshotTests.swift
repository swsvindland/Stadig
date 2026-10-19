import Foundation
import MindEngine
import SystemCore
import SystemStore
import Testing

@testable import MindTrack

/// What the widgets show: today's session as Today shows it, the week's count, and how a snapshot
/// reads once its day has gone by.
@MainActor
struct WidgetSnapshotTests {
    @Test func beforeSetupItAsksToSetUp() {
        let snapshot = WidgetBridge.snapshot(for: TestApp.model())
        #expect(snapshot.status == .setUp)
        #expect(snapshot == .empty)
    }

    @Test func aStudyDayShowsTheSessionAsTodayHasIt() throws {
        let model = TestApp.model()
        SampleData.seedIfEmpty(model)
        let plan = try #require(model.analysis?.today, "a Wednesday is a study day")
        let snapshot = WidgetBridge.snapshot(for: model)
        #expect(snapshot.status == .today)
        #expect(snapshot.headline == plan.headline)
        #expect(snapshot.parts.map(\.title) == plan.parts.map(\.title))
        #expect(snapshot.parts.map(\.minutes) == plan.parts.map(\.minutes))
        #expect(snapshot.symbols == plan.domains.map(\.symbol))
        #expect(snapshot.day == model.today)
        #expect(snapshot.plannedThisWeek > 0)
        #expect(snapshot.doneThisWeek <= snapshot.plannedThisWeek)
    }

    @Test func afterASessionItShowsWhatTodayShows() throws {
        let clock = TestClock()
        let model = TestApp.onboardedModel(clock: clock)
        model.startToday()
        Student.answer(model, steps: 12, clock: clock)
        clock.advance(30)
        model.endSession()
        let analysis = try #require(model.analysis)
        #expect(analysis.doneToday.count == 1)
        let snapshot = WidgetBridge.snapshot(for: model)
        // Today's card: the session again while it still waits (left early), otherwise done.
        if let plan = analysis.today {
            #expect(snapshot.status == .today)
            #expect(snapshot.headline == plan.headline)
        } else {
            #expect(snapshot.status == .done)
            #expect(snapshot.headline == "Done for today")
            #expect(snapshot.symbols == analysis.doneToday[0].domains.map(\.symbol))
        }
    }

    @Test func aSnapshotFromAnEarlierDayNudgesToOpenTheApp() {
        var snapshot = MindSnapshot.sample
        let written = Day(year: 2026, month: 10, day: 14)
        snapshot.day = written
        snapshot.nextDay = written.adding(days: 1)
        #expect(snapshot.reading(on: written) == snapshot, "on its own day it reads as written")

        let tomorrow = snapshot.reading(on: written.adding(days: 1))
        #expect(tomorrow.headline == "Study day: open Mind Track")
        #expect(tomorrow.parts.isEmpty)
        #expect(tomorrow.doneThisWeek == snapshot.doneThisWeek, "same week")

        let nextWeek = snapshot.reading(on: written.startOfWeek.adding(days: 8))
        #expect(nextWeek.headline == "Open Mind Track for today's plan")
        #expect(nextWeek.doneThisWeek == 0, "a new week counts from zero")
    }

    @Test func savingTheSameSnapshotTwiceWritesOnce() throws {
        let url = TestApp.folder().appending(path: "widget.json")
        var snapshot = MindSnapshot.sample
        #expect(try snapshot.save(to: url))
        snapshot.updated = Date().addingTimeInterval(60)
        #expect(try !snapshot.save(to: url), "only the stamp moved")
        snapshot.dueReviews += 1
        #expect(try snapshot.save(to: url))
        #expect(MindSnapshot.load(from: url) == snapshot)
    }

    @Test func aTestModelNeverWritesTheRealWidgetsSnapshot() {
        // Its shared container is a temporary folder, not the App Group: update leaves the real one alone.
        let model = TestApp.model()
        SampleData.seedIfEmpty(model)
        #expect(!model.shared.isAppGroup)
        WidgetBridge.update(model)
    }
}
