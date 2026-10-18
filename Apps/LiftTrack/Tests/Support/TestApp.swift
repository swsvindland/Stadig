import Foundation
import HealthBridge
import LiftEngine
import SystemCore
import SystemStore

@testable import LiftTrack

/// One install of the app for a test: an in-memory store and a fresh temporary folder for the shared
/// container, the session in progress and the widget snapshot. Models built from it share them, as a
/// relaunch does, so a test can drop one model and open the next over what it left.
@MainActor
struct TestApp {
    let folder: URL
    let store: RecordStore
    let shared: SharedContainer

    init() {
        // Nothing here reads or writes Health; the test host has already switched it off.
        HealthBridge.shared.disable()
        folder = URL.temporaryDirectory.appending(path: "LiftTrackTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        // A name of its own, so no two tests could ever share an in-memory store.
        store = RecordStore(name: "LiftTrackTests-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: true)
        shared = Self.container(in: folder)
    }

    /// The shared container another app on the same phone sees: the same folder, its own instance.
    /// Never an App Group: a simulator may hand out a folder for any group id, a made-up one included,
    /// and every test would then share it.
    static func container(in folder: URL) -> SharedContainer {
        SharedContainer(directory: folder.appending(path: "SystemShared", directoryHint: .isDirectory))
    }

    var liveURL: URL { folder.appending(path: "live-session.json") }
    var widgetURL: URL { folder.appending(path: "widget.json") }

    /// A model as the app builds one at launch, over this install's store and files.
    func model() -> AppModel {
        AppModel(store: store, shared: shared, liveURL: liveURL, widgetURL: widgetURL)
    }

    /// A model that has been through onboarding: four days a week, a full gym, in kilograms.
    func onboarded(saveToHealth: Bool = false) -> AppModel {
        let model = model()
        Self.onboard(model, saveToHealth: saveToHealth)
        return model
    }

    static func profile() -> SharedProfile {
        SharedProfile(
            goals: [.stronger], schedule: TrainingSchedule(daysPerWeek: 4, minutesPerSession: 60), equipment: .fullGym,
            experience: .intermediate, sex: .male, birthYear: 1990, heightCm: 180,
            units: UnitPreference(weight: .kg, length: .cm), createdBy: .liftTrack)
    }

    static func onboard(_ model: AppModel, saveToHealth: Bool = false) {
        let gym = Gym.preset(.fullGym, unit: .kg)
        model.completeOnboarding(
            profile: profile(), settings: LiftSettings(selfReportedPhase: .maintaining, saveToHealth: saveToHealth),
            gym: gym, measurements: BodyMeasurements(day: .today, weightKg: 82, waistCm: 86))
    }
}

extension AppModel {
    /// Logs the session's next `count` sets the way a steady lifter would: the prescription (or 20 kg
    /// while finding a weight), rated Just right; drills, conditioning and the sauna as planned.
    func logNext(_ count: Int, now: Date = Date()) {
        for _ in 0..<count {
            guard let live, let (i, s) = live.current, let environment else { return }
            let item = live.items[i]
            let prescription = item.sets[s].prescription
            update { session in
                if item.plan.conditioning != nil {
                    session.logConditioning(
                        item: i, minutes: item.plan.conditioning?.minutes ?? 10, averageHeartRate: nil, zoneMinutes: [:], now: now)
                } else if item.plan.role == .recovery {
                    session.logHeat(item: i, minutes: 10, temperatureC: 80, rating: .orange, now: now)
                } else if !item.plan.isStrength {
                    session.log(
                        item: i, set: s, reps: prescription.targetReps, loadKg: nil, rating: nil, seconds: prescription.seconds,
                        environment: environment, now: now)
                } else {
                    let rating: SetRating? = prescription.kind == .warmup || prescription.kind == .repOut ? nil : .orange
                    session.log(
                        item: i, set: s, reps: prescription.targetReps, loadKg: prescription.loadKg ?? 20, rating: rating,
                        environment: environment, now: now)
                }
                session.endRest(now: now)
            }
        }
    }

    /// Logs until a strength work set is in, so the record has lifting in it.
    func logUntilAWorkSet() {
        for _ in 0..<60 {
            if live?.items.contains(where: { $0.plan.isStrength && $0.loggedSets.contains { $0.kind.countsAsWork } }) == true { return }
            logNext(1)
        }
    }
}
