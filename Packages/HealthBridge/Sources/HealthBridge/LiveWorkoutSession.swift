#if os(watchOS)
import Foundation
import HealthKit
import Observation

/// The Watch's live workout: HKWorkoutSession + HKLiveWorkoutBuilder, streaming heart rate.
@MainActor @Observable
public final class LiveWorkoutSession: NSObject {
    /// Latest bpm.
    public private(set) var heartRate: Double?
    public private(set) var averageHeartRate: Double?
    /// Active energy so far, kcal.
    public private(set) var activeEnergy: Double?
    /// True while the session is running; false when paused or ended.
    public private(set) var isRunning = false
    /// Every bpm reading this session, oldest first.
    public private(set) var samples: [(date: Date, bpm: Double)] = []
    /// Called on the main actor with each new bpm reading.
    @ObservationIgnored public var onHeartRate: ((Double) -> Void)?
    /// Data the iPhone sent over a mirrored session.
    @ObservationIgnored public var onRemoteData: (([Data]) -> Void)?
    /// The iPhone ended a mirrored session without saying how.
    @ObservationIgnored public var onEndedRemotely: (() -> Void)?
    /// Mirrored to the iPhone, which leads the session.
    public private(set) var isMirrored = false

    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?

    public override init() { super.init() }

    /// Starts a session and begins collecting. The workout carries `syncID` as its sync identifier
    /// (version 1), so the phone can later replace it with a higher version.
    public func start(activity: HKWorkoutActivityType = .traditionalStrengthTraining, syncID: UUID) async throws {
        try await begin(activity: activity, syncID: syncID)
    }

    /// Starts a workout for a session the iPhone leads: this Watch measures, the phone shows it.
    /// The workout gets its sync id when the phone says it's done (``end(syncID:)``).
    public func startMirrored(activity: HKWorkoutActivityType = .traditionalStrengthTraining) async throws {
        try await begin(activity: activity, syncID: nil)
        try await session?.startMirroringToCompanionDevice()
        isMirrored = true
    }

    /// Sends data to the iPhone over a mirrored session.
    public func send(_ data: Data) async {
        guard let session, isMirrored else { return }
        try? await session.sendToRemoteWorkoutSession(data: data)
    }

    private func begin(activity: HKWorkoutActivityType, syncID: UUID?) async throws {
        guard session == nil else { return }
        guard let store = HealthBridge.shared.store else { throw HKError(.errorHealthDataUnavailable) }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        configuration.locationType = .indoor
        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        heartRate = nil
        averageHeartRate = nil
        activeEnergy = nil
        samples = []

        let start = Date()
        session.startActivity(with: start)
        do {
            try await builder.beginCollection(at: start)
            if let syncID { try await builder.addMetadata([HKMetadataKeySyncIdentifier: syncID.uuidString, HKMetadataKeySyncVersion: 1]) }
            isRunning = true
        } catch {
            session.end()
            builder.discardWorkout()
            reset()
            throw error
        }
    }

    public func pause() {
        session?.pause()
        isRunning = false
    }

    public func resume() {
        guard let session else { return }
        session.resume()
        isRunning = true
    }

    /// Ends the session and saves the workout with the sync id metadata; returns the saved workout's end date.
    /// A mirrored workout takes its sync id here, from the phone's session.
    public func end(syncID: UUID? = nil) async -> Date? {
        guard let session, let builder else { return nil }
        let endDate = Date()
        session.end()
        defer { reset() }
        do {
            if let syncID { try await builder.addMetadata([HKMetadataKeySyncIdentifier: syncID.uuidString, HKMetadataKeySyncVersion: 1]) }
            try await builder.endCollection(at: endDate)
            return try await builder.finishWorkout()?.endDate
        } catch {
            builder.discardWorkout()
            return nil
        }
    }

    /// Ends the session without saving anything.
    public func discard() async {
        guard let session, let builder else { return }
        session.end()
        builder.discardWorkout()
        reset()
    }

    private func reset() {
        session = nil
        builder = nil
        isRunning = false
        isMirrored = false
    }

    private func record(from source: HKWorkoutSession, latest: (date: Date, bpm: Double)?, average: Double?, energy: Double?) {
        guard source === session else { return }
        if let average { averageHeartRate = average }
        if let energy { activeEnergy = energy }
        guard let latest, samples.last?.date != latest.date else { return }
        heartRate = latest.bpm
        samples.append(latest)
        if samples.count > 1, samples[samples.count - 2].date > latest.date { samples.sort { $0.date < $1.date } }
        onHeartRate?(latest.bpm)
    }

    private func sessionChanged(_ source: HKWorkoutSession, running: Bool, ended: Bool = false) {
        guard source === session else { return }
        isRunning = running
        if ended, isMirrored { onEndedRemotely?() }
    }

    private func received(_ data: [Data], from source: HKWorkoutSession) {
        guard source === session else { return }
        onRemoteData?(data)
    }
}

extension LiveWorkoutSession: HKWorkoutSessionDelegate {
    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                           from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in self.sessionChanged(workoutSession, running: toState == .running, ended: toState == .ended) }
    }

    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in self.received(data, from: workoutSession) }
    }

    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor in self.sessionChanged(workoutSession, running: false) }
    }
}

extension LiveWorkoutSession: HKLiveWorkoutBuilderDelegate {
    nonisolated public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated public func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let session = workoutBuilder.workoutSession else { return }
        let heartRate = collectedTypes.contains(HealthTypes.heartRate) ? workoutBuilder.statistics(for: HealthTypes.heartRate) : nil
        let latest = heartRate?.mostRecentQuantity().map {
            (date: heartRate?.mostRecentQuantityDateInterval()?.start ?? Date(), bpm: $0.doubleValue(for: HealthTypes.bpm))
        }
        let average = heartRate?.averageQuantity()?.doubleValue(for: HealthTypes.bpm)
        let energy = collectedTypes.contains(HealthTypes.activeEnergy)
            ? workoutBuilder.statistics(for: HealthTypes.activeEnergy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            : nil
        Task { @MainActor in self.record(from: session, latest: latest, average: average, energy: energy) }
    }
}
#endif
