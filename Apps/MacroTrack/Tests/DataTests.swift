import Foundation
import MealPlanner
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// Settings' "Your data": the CSV export, a backup, and restoring one.
@MainActor
@Suite(.serialized)
struct DataTests {
    @Test func theCSVExportWritesEveryTable() throws {
        let model = TestEnvironment().model()
        SampleData.seedIfEmpty(model)
        let urls = try model.exportCSV()
        #expect(urls.count >= 4, "diary, weight, targets and days at least")
        for url in urls {
            let data = try Data(contentsOf: url)
            #expect(data.count > 3, "\(url.lastPathComponent) has a header")
        }
        #expect(urls.contains { $0.lastPathComponent.lowercased().contains("diary") || $0.lastPathComponent.lowercased().contains("food") })
    }

    @Test func aBackupRestoresIntoAFreshInstall() async throws {
        let original = TestEnvironment().model()
        SampleData.seedIfEmpty(original)
        let trip = LifeModePeriod(kind: .vacation, start: original.today, end: original.today.adding(days: 3), createdBy: .macroTrack)
        original.save(lifeMode: trip)
        let url = try await original.backupFile()

        let fresh = TestEnvironment().model()
        #expect(!fresh.onboarded)
        let summary = try await fresh.restore(from: url)
        #expect(summary.records > 0)
        #expect(fresh.onboarded)
        #expect(fresh.entries.count == original.entries.count)
        #expect(fresh.weighIns.count == original.weighIns.count)
        #expect(fresh.lifeModes.map(\.id) == [trip.id])
    }

    @Test func aMealPlanStoredBeforeOneDishReadsAsTwoDishes() async throws {
        let original = TestEnvironment().model()
        SampleData.seedIfEmpty(original)
        let plan = original.makeMealPlan(preferences: PlanPreferences(slots: [.lunch, .dinner]), start: original.today.adding(days: 1))
        var json = try #require(JSONSerialization.jsonObject(with: SystemJSON.encoder().encode(plan)) as? [String: Any])
        var preferences = try #require(json["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "oneDish")
        json["preferences"] = preferences
        let file = BackupFile(
            app: .macroTrack,
            records: [
                BackupRecord(
                    kind: MealPlan.kind, uuid: plan.id, updatedAt: plan.updatedAt, schemaVersion: 1,
                    payload: try JSONSerialization.data(withJSONObject: json), deleted: false)
            ])
        let url = TestEnvironment().folder.appending(path: "Macro Track.macrobackup")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SystemJSON.encoder().encode(file).write(to: url)

        let fresh = TestEnvironment().model()
        let summary = try await fresh.restore(from: url)
        #expect(summary.records == 1)
        let restored = try #require(fresh.mealPlans.first { $0.id == plan.id })
        #expect(restored.preferences.oneDish == false)
        #expect(restored.recipes == plan.recipes && restored.meals == plan.meals)
    }

    @Test func anotherAppsBackupIsRefusedBeforeAnythingIsWritten() throws {
        let lift = RecordStore(name: "LiftTrackTests-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: true)
        lift.save(ProfileRecord(.sample(createdBy: .liftTrack)))
        let url = TestEnvironment().folder.appending(path: "Lift Track.liftbackup")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lift.exportBackup(app: .liftTrack, shared: nil).write(to: url)

        let model = TestEnvironment().model()
        let error = #expect(throws: SystemStoreError.self) { try model.restore(from: url) }
        #expect(error?.localizedDescription == "This backup is from Lift Track. Restore it there.")
        #expect(!model.onboarded)
        #expect(model.store.all(ProfileRecord.self).isEmpty)
    }
}
