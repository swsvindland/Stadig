import Foundation
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// The model's observers (the shared container, the store) and its background searches hold it
/// weakly, so a model nobody uses goes away.
@MainActor
struct LifetimeTests {
    @Test func aFreshModelDeallocates() {
        weak var released: AppModel?
        do {
            let model = TestEnvironment().model()
            released = model
            #expect(released != nil)
        }
        #expect(released == nil)
    }

    @Test func aModelThatLoggedAndSearchedDeallocates() async throws {
        weak var released: AppModel?
        do {
            let model = TestEnvironment().model()
            SampleData.seedIfEmpty(model)
            model.log([try model.entry(foodID: Foods.bananaID, grams: 120)])
            model.save(lifeMode: .init(kind: .vacation, start: model.today, end: model.today.adding(days: 2), createdBy: .macroTrack))
            released = model
        }
        // The personal-food and nutrient searches it started may still be running; they hold it weakly.
        #expect(released == nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(released == nil)
    }
}

/// Another device's edits, as CloudKit imports them while the app is open: the store tells the
/// model, and the model reloads. Over a store on disk, since only those hear of changes made elsewhere.
@MainActor
struct RemoteChangeTests {
    @Test func anImportWhileOnboardingIsOnScreenFinishesIt() async throws {
        let name = "MacroTrackTests-\(UUID().uuidString)"
        defer { Self.removeStore(name) }
        let environment = TestEnvironment(store: RecordStore(name: name, cloudKitContainer: nil, inMemory: false))
        let model = environment.model()
        #expect(!model.onboarded)

        // The other device's setup lands in the same database through another connection.
        let elsewhere = RecordStore(name: name, cloudKitContainer: nil, inMemory: false)
        elsewhere.save(ProfileRecord(.sample()))
        elsewhere.save(MacroSettings(id: MacroSettings.singletonID, onboardedAt: Date(), assessmentStart: model.today))
        NotificationCenter.default.post(name: Notification.Name("NSPersistentStoreRemoteChangeNotification"), object: nil)

        // The store waits for a quiet moment, then needs the main actor, which the other suites
        // share: a generous wait, over as soon as it lands.
        #expect(await eventually(timeout: .seconds(30)) { model.onboarded })
        #expect(model.profile?.heightCm == 180)
    }

    private static func removeStore(_ name: String) {
        let folder = URL.applicationSupportDirectory.appending(path: "SystemStore", directoryHint: .isDirectory)
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: folder.appending(path: "\(name).store\(suffix)"))
        }
    }
}
