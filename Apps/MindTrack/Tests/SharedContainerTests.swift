import Foundation
import MindEngine
import SystemCore
import SystemStore
import Testing

@testable import MindTrack

/// What Mind Track publishes to the shared container and reads from it: the hub summary, life modes
/// set in any app (deletes included), and backups.
@MainActor
struct SharedContainerTests {
    // MARK: Life modes

    @Test func aLifeModeSavedHereIsSharedAndReachesTheOtherApps() throws {
        let clock = TestClock()
        let shared = TestApp.sharedContainer()
        let mind = TestApp.onboardedModel(shared: shared, clock: clock)
        let other = TestApp.onboardedModel(shared: shared, clock: clock)
        let today = mind.today

        let trip = LifeModePeriod(kind: .vacation, start: today, end: today.adding(days: 4), createdBy: .knowledge)
        #expect(mind.save(lifeMode: trip))
        #expect(mind.lifeModes.map(\.id) == [trip.id])
        #expect(mind.analysis?.phase == .paused(.vacation), "a vacation pauses Mind Track")
        let file = try #require(shared.read(.lifeModes))
        #expect(file.map(\.id) == [trip.id])

        // Another app (or this app on another device) reads the file and keeps its own copy.
        other.readShared()
        #expect(other.lifeModes.map(\.id) == [trip.id])
        #expect(other.store.all(LifeModeRecord.self).map(\.id) == [trip.id])
        #expect(other.analysis?.phase == .paused(.vacation))
    }

    @Test func aDeleteMadeElsewhereIsHonoured() throws {
        let clock = TestClock()
        let shared = TestApp.sharedContainer()
        let mind = TestApp.onboardedModel(shared: shared, clock: clock)
        let other = TestApp.onboardedModel(shared: shared, clock: clock)
        let today = mind.today
        let trip = LifeModePeriod(kind: .vacation, start: today, end: today.adding(days: 4), createdBy: .knowledge)
        mind.save(lifeMode: trip)
        other.readShared()

        clock.advance(60)
        other.delete(lifeMode: trip.id)
        #expect(other.lifeModes.isEmpty)
        let file = try #require(shared.read(.lifeModes))
        #expect(file.count == 1)
        #expect(file.first?.isDeleted == true, "the delete is shared as a tombstone")

        mind.readShared()
        #expect(mind.lifeModes.isEmpty, "the app that made it doesn't bring it back")
        #expect(mind.store.all(LifeModeRecord.self).first?.period.isDeleted == true, "and its synced copy is the tombstone, for its other devices")
        #expect(mind.analysis?.phase.isAssessment == true, "no longer paused")

        // Reading again, as each app does when the file changes, keeps it deleted.
        mind.readShared()
        other.readShared()
        #expect(mind.lifeModes.isEmpty && other.lifeModes.isEmpty)
    }

    @Test func deletingAnotherAppsPeriodSharesTheDelete() throws {
        let clock = TestClock()
        let shared = TestApp.sharedContainer()
        let model = TestApp.onboardedModel(shared: shared, clock: clock)
        let today = model.today
        let ill = LifeModePeriod(
            kind: .illness(.systemic), start: today.adding(days: -1), createdBy: .liftTrack,
            updatedAt: clock.now.addingTimeInterval(-3600))
        try shared.write([ill], to: .lifeModes, by: .liftTrack)

        model.readShared()
        #expect(model.lifeModes.map(\.id) == [ill.id])
        #expect(model.analysis?.phase == .paused(.illness(.systemic)))

        clock.advance(10)
        model.delete(lifeMode: ill.id)
        let file = try #require(shared.read(.lifeModes))
        #expect(file.map(\.id) == [ill.id])
        #expect(file.first?.deletedAt == clock.now)
        #expect(model.lifeModes.isEmpty)
    }

    @Test func anOlderCopyDoesntUndoANewerEdit() throws {
        let clock = TestClock()
        let shared = TestApp.sharedContainer()
        let model = TestApp.onboardedModel(shared: shared, clock: clock)
        let today = model.today
        var trip = LifeModePeriod(kind: .vacation, start: today, end: today.adding(days: 2), createdBy: .knowledge)
        model.save(lifeMode: trip)

        // Lift Track still has the first version and writes it back with its own change elsewhere.
        let stale = try #require(shared.read(.lifeModes))
        clock.advance(60)
        trip.end = today.adding(days: 6)
        model.save(lifeMode: trip)
        try shared.write(stale, to: .lifeModes, by: .liftTrack)

        model.readShared()
        #expect(model.lifeModes.first?.end == today.adding(days: 6), "newest edit wins")
        #expect(shared.read(.lifeModes)?.first?.end == today.adding(days: 6), "and goes back to the file")
    }

    @Test func aPeriodTheEditorShouldntOfferIsRefused() {
        let shared = TestApp.sharedContainer()
        let model = TestApp.onboardedModel(shared: shared)
        let today = model.today
        let backwards = LifeModePeriod(kind: .vacation, start: today, end: today.adding(days: -3), createdBy: .knowledge)
        #expect(!model.save(lifeMode: backwards))
        let openTrip = LifeModePeriod(kind: .crunch(CrunchDials()), start: today, createdBy: .knowledge)
        #expect(!model.save(lifeMode: openTrip), "only illness and injury run until they're better")
        #expect(model.lifeModes.isEmpty)
        #expect(model.store.all(LifeModeRecord.self).isEmpty)
        #expect(shared.read(.lifeModes) == nil)
        #expect(model.save(lifeMode: LifeModePeriod(kind: .illness(.aboveNeck), start: today, createdBy: .knowledge)))
    }

    @Test func readingTheSharedFilesAgainWritesNothing() throws {
        let clock = TestClock()
        let shared = TestApp.sharedContainer()
        let model = TestApp.onboardedModel(shared: shared, clock: clock)
        let today = model.today
        model.save(lifeMode: LifeModePeriod(kind: .vacation, start: today.adding(days: 3), end: today.adding(days: 5), createdBy: .knowledge))
        let lifeModes = try #require(shared.envelope(.lifeModes)).writtenAt
        let summary = try #require(shared.envelope(.summary(.knowledge))).writtenAt

        // Every write wakes every app, this one included: reading again must not write again.
        clock.advance(120)
        model.readShared()
        model.readShared()
        model.recompute()
        #expect(shared.envelope(.lifeModes)?.writtenAt == lifeModes)
        #expect(shared.envelope(.summary(.knowledge))?.writtenAt == summary)
    }

    @Test func aLifeModeFromAnOlderBuildReadsAsLive() async throws {
        // A backup (or a sync) from a build before deletes were shared: schema 1, no deletedAt.
        let clock = TestClock()
        let model = TestApp.onboardedModel(clock: clock)
        let today = model.today
        let period = LifeModePeriod(kind: .vacation, start: today, end: today.adding(days: 3), createdBy: .liftTrack, updatedAt: clock.now)
        var json = try #require(try JSONSerialization.jsonObject(with: SystemJSON.encoder().encode(LifeModeRecord(period))) as? [String: Any])
        var inner = try #require(json["period"] as? [String: Any])
        inner["deletedAt"] = nil
        json["period"] = inner
        let payload = try JSONSerialization.data(withJSONObject: json)
        let backup = BackupFile(
            app: .knowledge,
            records: [
                BackupRecord(kind: LifeModeRecord.kind, uuid: period.id, updatedAt: clock.now, schemaVersion: 1, payload: payload, deleted: false)
            ])
        let url = TestApp.folder().appending(path: "old.mindbackup")
        try SystemJSON.encoder().encode(backup).write(to: url)

        let summary = try await model.restore(from: url)
        #expect(summary.records == 1)
        #expect(model.lifeModes.map(\.id) == [period.id])
        #expect(model.lifeModes.first?.deletedAt == nil)
        #expect(model.analysis?.phase == .paused(.vacation))
    }

    // MARK: The hub summary

    @Test func theSummaryIsPublishedOnceOnboarded() throws {
        let clock = TestClock()
        let shared = TestApp.sharedContainer()
        let model = TestApp.model(shared: shared, clock: clock)
        #expect(shared.read(.summary(.knowledge)) == nil, "nothing to say before setup")
        model.completeOnboarding(TestApp.settings([.maths, .writing]), booksRead: [])
        let envelope = try #require(shared.envelope(.summary(.knowledge)))
        #expect(envelope.writtenBy == .knowledge)
        #expect(envelope.payload.app == .knowledge)
        #expect(!envelope.payload.stats.isEmpty)
        #expect(envelope.payload.updated == clock.now, "dated by the model's clock")
    }

    @Test func aRelaunchDoesntRepublishAnUnchangedSummary() throws {
        let clock = TestClock()
        let store = TestApp.store()
        let shared = TestApp.sharedContainer()
        _ = TestApp.onboardedModel(store: store, shared: shared, clock: clock)
        let first = try #require(shared.envelope(.summary(.knowledge)))
        clock.advance(600)
        _ = TestApp.model(store: store, shared: shared, clock: clock)
        let second = try #require(shared.envelope(.summary(.knowledge)))
        #expect(second.writtenAt == first.writtenAt)
        #expect(second.payload.updated == first.payload.updated, "the summary's date says when its content last changed")
    }

    // MARK: Backups

    @Test func aBackupRestoresIntoAFreshInstall() async throws {
        let clock = TestClock()
        let model = TestApp.onboardedModel([.maths, .reading], clock: clock)
        model.startToday()
        Student.answer(model, steps: 10, clock: clock)
        model.endSession()
        model.save(book: Book(title: "Emma", author: "Jane Austen", tier: 6, pages: 470, genres: [.classics], status: .reading))
        let url = try await model.backupFile()

        let fresh = TestApp.model(clock: clock)
        let summary = try await fresh.restore(from: url)
        #expect(summary.records > 0)
        #expect(fresh.onboarded)
        #expect(fresh.sessions.map(\.id) == model.sessions.map(\.id))
        #expect(fresh.books.map(\.title) == ["Emma"])
        #expect(Set(fresh.cards.map(\.key)) == Set(model.cards.map(\.key)))
    }

    @Test func anotherAppsBackupIsRefusedWithoutChangingAnything() async throws {
        let model = TestApp.onboardedModel()
        let lift = BackupFile(
            app: .liftTrack,
            records: [
                BackupRecord(kind: "settings", uuid: UUID(), updatedAt: Date(), schemaVersion: 1, payload: Data("{}".utf8), deleted: false)
            ])
        let url = TestApp.folder().appending(path: "lift.liftbackup")
        try SystemJSON.encoder().encode(lift).write(to: url)
        let before = model.settings
        await #expect(throws: SystemStoreError.self) { try await model.restore(from: url) }
        #expect(model.settings == before)
    }

    @Test func theExportWritesATableForEachRecordKind() throws {
        let clock = TestClock()
        let model = TestApp.onboardedModel(clock: clock)
        model.startToday()
        Student.answer(model, steps: 6, clock: clock)
        model.endSession()
        let urls = try model.exportCSV()
        #expect(!urls.isEmpty)
        for url in urls {
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }
        let sessions = try #require(urls.first { $0.lastPathComponent.hasPrefix("sessions") })
        let rows = try String(contentsOf: sessions, encoding: .utf8).split(whereSeparator: \.isNewline)
        #expect(rows.count == 2, "a header and today's session")
    }
}
