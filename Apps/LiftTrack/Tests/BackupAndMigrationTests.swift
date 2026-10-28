import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import SystemStore
import Testing

@testable import LiftTrack

/// Backups in and out, and records stored by earlier versions of the app: a migration that breaks
/// makes settings unreadable (onboarding again) or loses measurements.
@MainActor
@Suite("Backups and migrations")
struct BackupAndMigrationTests {
    private func write(_ file: BackupFile, in app: TestApp) throws -> URL {
        try FileManager.default.createDirectory(at: app.folder, withIntermediateDirectories: true)
        let url = app.folder.appending(path: "test.liftbackup")
        try SystemJSON.encoder().encode(file).write(to: url)
        return url
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: SystemJSON.encoder().encode(value)) as? [String: Any])
    }

    private func record(_ kind: String, id: UUID, version: Int, _ json: [String: Any]) throws -> BackupRecord {
        BackupRecord(
            kind: kind, uuid: id, updatedAt: Date(), schemaVersion: version, payload: try JSONSerialization.data(withJSONObject: json),
            deleted: false)
    }

    @Test("Settings stored before focus areas existed read as no focus, and stay onboarded")
    func settingsVersion1() async throws {
        let app = TestApp()
        var settings = LiftSettings(selfReportedPhase: .bulking, saveToHealth: false, onboardedAt: Date().addingTimeInterval(-86_400 * 30))
        settings.focus = [.arms]
        var json = try object(settings)
        json.removeValue(forKey: "focus")
        let profile = ProfileRecord(TestApp.profile())
        let file = BackupFile(
            app: .liftTrack,
            records: [
                try record(LiftSettings.kind, id: settings.id, version: 1, json),
                try record(ProfileRecord.kind, id: profile.id, version: ProfileRecord.schemaVersion, object(profile)),
            ])
        let model = app.model()
        let summary = try await model.importBackup(from: write(file, in: app))
        #expect(summary.records == 2)
        #expect(model.settings.id == settings.id)
        #expect(model.settings.focus.isEmpty)
        #expect(model.settings.selfReportedPhase == .bulking)
        #expect(model.onboarded)
    }

    @Test("Measurements stored when hips meant the widest point move to glutes")
    func measurementsVersion1() async throws {
        let app = TestApp()
        let measurements = BodyMeasurements(day: Day.today.adding(days: -40), waistCm: 86, glutesCm: 99)
        var json = try object(MeasurementRecord(measurements))
        var inner = try #require(json["measurements"] as? [String: Any])
        inner["hipsCm"] = inner.removeValue(forKey: "glutesCm")
        json["measurements"] = inner
        let model = app.onboarded()
        try await model.importBackup(
            from: write(BackupFile(app: .liftTrack, records: [try record(MeasurementRecord.kind, id: measurements.id, version: 1, json)]), in: app))
        let restored = try #require(model.measurements.first { $0.id == measurements.id })
        #expect(restored.glutesCm == 99)
        #expect(restored.hipsCm == nil)
        #expect(restored.waistCm == 86)
    }

    @Test("A life mode stored before deletes were shared reads as live")
    func lifeModeVersion1() async throws {
        let app = TestApp()
        let trip = LifeModePeriod(kind: .vacation, start: Day.today.adding(days: 2), end: Day.today.adding(days: 6), createdBy: .liftTrack)
        var json = try object(LifeModeRecord(trip))
        if var period = json["period"] as? [String: Any] {
            period.removeValue(forKey: "deletedAt")
            json["period"] = period
        }
        let model = app.onboarded()
        try await model.importBackup(
            from: write(BackupFile(app: .liftTrack, records: [try record(LifeModeRecord.kind, id: trip.id, version: 1, json)]), in: app))
        #expect(model.lifeModes.map(\.id) == [trip.id])
    }

    @Test("A block stored before blocks had a focus reads as none, with its days intact")
    func mesocycleVersion1() async throws {
        let app = TestApp()
        let model = app.onboarded()
        var block = try #require(model.mesocycles.first)
        block.id = UUID()
        var json = try object(block)
        json.removeValue(forKey: "focus")
        try await model.importBackup(
            from: write(BackupFile(app: .liftTrack, records: [try record(Mesocycle.kind, id: block.id, version: 1, json)]), in: app))
        let restored = try #require(model.mesocycles.first { $0.id == block.id })
        #expect(restored.focus == nil)
        #expect(restored.days == block.days)
        #expect(restored.block == block.block)
    }

    @Test("A backup brings everything back on a fresh install")
    func backupRoundTrip() async throws {
        let first = TestApp()
        let model = first.onboarded()
        model.start(try #require(model.plan()))
        model.logUntilAWorkSet()
        model.finish(feedback: nil)
        model.save(lifeMode: LifeModePeriod(kind: .vacation, start: Day.today.adding(days: 5), end: Day.today.adding(days: 8), createdBy: .liftTrack))
        let url = try await model.exportBackup()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.pathExtension == "liftbackup")

        let second = TestApp()
        let restored = second.model()
        #expect(!restored.onboarded)
        let summary = try await restored.importBackup(from: url)
        #expect(summary.records > 0)
        #expect(restored.onboarded)
        #expect(restored.sessions.map(\.id) == model.sessions.map(\.id))
        #expect(restored.mesocycles.map(\.id) == model.mesocycles.map(\.id))
        #expect(restored.lifeModes.map(\.id) == model.lifeModes.map(\.id))
        #expect(second.shared.read(.profile) != nil)
    }

    @Test("Another app's backup is refused before anything is written")
    func otherAppsBackupIsRefused() async throws {
        let app = TestApp()
        let model = app.model()
        let profile = ProfileRecord(TestApp.profile())
        let file = BackupFile(
            app: .macroTrack, records: [try record(ProfileRecord.kind, id: profile.id, version: ProfileRecord.schemaVersion, object(profile))])
        await #expect(throws: SystemStoreError.self) { try await model.importBackup(from: write(file, in: app)) }
        #expect(model.profile == nil)
        #expect(app.store.all(ProfileRecord.self).isEmpty)
    }
}
