import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import SystemStore
import Testing

@testable import LiftTrack

/// What Stadig Lift publishes to the App Group and what it reads from the other apps, life modes most
/// of all: they apply across every app, so an edit or a delete in one has to reach the others.
@MainActor
@Suite("Shared container")
struct SharedContainerTests {
    @Test("The summary and the calendar are published once there's an analysis, and not rewritten when nothing changed")
    func publishesSummaryAndCalendar() throws {
        let app = TestApp()
        let model = app.onboarded()
        let summary = try #require(app.shared.envelope(.summary(.liftTrack)))
        #expect(summary.writtenBy == .liftTrack)
        #expect(summary.payload.app == .liftTrack)
        let calendar = try #require(app.shared.envelope(.calendar))
        #expect(calendar.payload.publishedBy == .liftTrack)
        #expect(calendar.payload.currentBlock?.start == .today)

        model.recompute()
        app.model().recompute()
        #expect(app.shared.envelope(.summary(.liftTrack))?.writtenAt == summary.writtenAt)
        #expect(app.shared.envelope(.calendar)?.writtenAt == calendar.writtenAt)
    }

    @Test("Stadig Macro's phase is read")
    func readsOtherApps() throws {
        let app = TestApp()
        let model = app.onboarded()
        let other = TestApp.container(in: app.folder)
        let phase = NutritionPhase(kind: .cut, ratePerWeek: -0.5, start: Day.today.adding(days: -10), source: .macroTrack)
        try other.write(NutritionSummary(phase: phase, maintenanceKcal: 2_600, days: []), to: .nutrition, by: .macroTrack)
        model.readShared()
        #expect(model.nutrition?.phase?.kind == .cut)
        #expect(model.analysis?.phase.kind == .cut)
    }

    @Test("A fast running in Stadig Macro is read, and a day into one, a session still to do today gets a word")
    func readsMacroTracksFast() throws {
        let app = TestApp()
        let model = app.onboarded()
        let other = TestApp.container(in: app.folder)
        // In whole seconds: the shared file keeps times to the millisecond.
        let fast = PublishedFast(start: Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 30 * 3600).rounded()), goalHours: 48)
        try other.write(NutritionSummary(phase: nil, maintenanceKcal: nil, days: [], fast: fast), to: .nutrition, by: .macroTrack)
        model.readShared()
        #expect(model.nutrition?.fast == fast)
        let analysis = try #require(model.analysis)
        // Whether today has a session to do depends on the weekday the test runs on.
        let sessionToDo = analysis.next?.scheduledToday == true && analysis.block?.week(of: model.today) != .deload
        #expect(analysis.actions.contains { $0.kind == .fasting } == sessionToDo)
    }

    // MARK: Life modes

    private func vacation(by app: AppID = .macroTrack, updatedAt: Date = Date()) -> LifeModePeriod {
        LifeModePeriod(kind: .vacation, start: Day.today.adding(days: 3), end: Day.today.adding(days: 9), createdBy: app, updatedAt: updatedAt)
    }

    @Test("A life mode another app shared is used here and kept in Stadig Lift's own store")
    func lifeModeFromAnotherApp() throws {
        let app = TestApp()
        let model = app.onboarded()
        let other = TestApp.container(in: app.folder)
        let trip = vacation()
        try other.write([trip], to: .lifeModes, by: .macroTrack)
        model.readShared()
        #expect(model.lifeModes.map(\.id) == [trip.id])
        // Kept in the synced store, so it reaches Stadig Lift on the person's other devices too.
        #expect(app.store.all(LifeModeRecord.self).map(\.period.id) == [trip.id])
    }

    @Test("A delete made in another app is honoured, and stays deleted after a relaunch")
    func deleteElsewhereIsHonoured() throws {
        let app = TestApp()
        let model = app.onboarded()
        let other = TestApp.container(in: app.folder)
        let trip = vacation(updatedAt: Date().addingTimeInterval(-60))
        try other.write([trip], to: .lifeModes, by: .macroTrack)
        model.readShared()
        #expect(model.lifeModes.count == 1)

        try other.write([trip.deleted(at: Date())], to: .lifeModes, by: .macroTrack)
        model.readShared()
        #expect(model.lifeModes.isEmpty)
        #expect(model.analysis?.life.active.isEmpty == true)
        // The tombstone is kept, in the store and the file, so older copies can't bring it back.
        #expect(app.store.all(LifeModeRecord.self).first?.period.isDeleted == true)
        #expect(app.shared.read(.lifeModes)?.first?.isDeleted == true)
        #expect(app.model().lifeModes.isEmpty)
    }

    @Test("A delete made here reaches the file as a tombstone, and an older copy from elsewhere doesn't bring it back")
    func deleteHereIsShared() throws {
        let app = TestApp()
        let model = app.onboarded()
        let trip = vacation(by: .liftTrack)
        #expect(model.save(lifeMode: trip))
        #expect(app.shared.read(.lifeModes)?.map(\.id) == [trip.id])

        model.delete(lifeMode: trip.id)
        #expect(model.lifeModes.isEmpty)
        let shared = try #require(app.shared.read(.lifeModes))
        #expect(shared.count == 1)
        #expect(shared.first?.isDeleted == true)

        // Another app still holding its old copy writes it back.
        let other = TestApp.container(in: app.folder)
        try other.write([trip], to: .lifeModes, by: .macroTrack)
        model.readShared()
        #expect(model.lifeModes.isEmpty)
        #expect(app.shared.read(.lifeModes)?.first?.isDeleted == true)
    }

    @Test("The newest edit of a period wins, wherever it was made")
    func newestEditWins() async throws {
        let app = TestApp()
        let model = app.onboarded()
        var trip = vacation(by: .liftTrack)
        model.save(lifeMode: trip)
        // Stadig Macro moves the end a day later, after Stadig Lift's save (edits are compared to the
        // millisecond, so each waits a little).
        try await Task.sleep(for: .milliseconds(20))
        let other = TestApp.container(in: app.folder)
        var theirs = try #require(other.read(.lifeModes)?.first)
        theirs.end = Day.today.adding(days: 10)
        theirs.updatedAt = Date()
        try other.write([theirs], to: .lifeModes, by: .macroTrack)
        model.readShared()
        #expect(model.lifeModes.first?.end == Day.today.adding(days: 10))
        // An edit made here afterwards wins in turn.
        trip.end = Day.today.adding(days: 8)
        try await Task.sleep(for: .milliseconds(20))
        model.save(lifeMode: trip)
        #expect(model.lifeModes.first?.end == Day.today.adding(days: 8))
    }

    @Test("A period that can't apply isn't saved: an open-ended vacation, an injury with nowhere hurt")
    func invalidPeriodsAreRefused() {
        let model = TestApp().onboarded()
        #expect(!model.save(lifeMode: LifeModePeriod(kind: .vacation, start: .today, createdBy: .liftTrack)))
        #expect(!model.save(lifeMode: LifeModePeriod(kind: .injury(Injury(parts: [], severity: .mild)), start: .today, createdBy: .liftTrack)))
        #expect(model.lifeModes.isEmpty)
        // Dates the wrong way round are put in order rather than refused.
        let backwards = LifeModePeriod(kind: .vacation, start: Day.today.adding(days: 9), end: Day.today.adding(days: 3), createdBy: .liftTrack)
        #expect(model.save(lifeMode: backwards))
        #expect(model.lifeModes.first?.start == Day.today.adding(days: 3))
        #expect(model.lifeModes.first?.end == Day.today.adding(days: 9))
    }

    @Test("Ending a period: yesterday when it started before today; called off when a vacation starts today; kept for today when an injury does")
    func endingAPeriod() throws {
        let model = TestApp().onboarded()
        let started = LifeModePeriod(
            kind: .crunch(CrunchDials()), start: Day.today.adding(days: -3), end: Day.today.adding(days: 3),
            createdBy: .liftTrack)
        model.save(lifeMode: started)
        #expect(model.canEnd(started))
        model.end(lifeMode: started)
        #expect(model.lifeModes.first { $0.id == started.id }?.end == Day.today.adding(days: -1))

        let trip = LifeModePeriod(kind: .vacation, start: .today, end: Day.today.adding(days: 4), createdBy: .liftTrack)
        model.save(lifeMode: trip)
        model.end(lifeMode: trip)
        #expect(!model.lifeModes.contains { $0.id == trip.id })

        let knee = LifeModePeriod(kind: .injury(Injury(parts: [InjuredPart(.knee)], severity: .mild)), start: .today, createdBy: .liftTrack)
        model.save(lifeMode: knee)
        model.end(lifeMode: knee)
        #expect(model.lifeModes.first { $0.id == knee.id }?.end == .today)

        // One still to come has nothing to end.
        #expect(
            !model.canEnd(LifeModePeriod(kind: .vacation, start: Day.today.adding(days: 5), end: Day.today.adding(days: 8), createdBy: .liftTrack)))
    }
}
