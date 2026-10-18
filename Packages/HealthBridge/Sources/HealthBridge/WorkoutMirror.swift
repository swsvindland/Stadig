#if os(iOS)
import Foundation
import HealthKit
import Observation

/// The iPhone's side of a workout the Watch runs beside a session led from the phone: the phone
/// asks the Watch to start one, the Watch mirrors it back, and its readings arrive as data.
@MainActor @Observable
public final class WorkoutMirror: NSObject {
    public static let shared = WorkoutMirror()

    /// A mirrored workout is live.
    public private(set) var isConnected = false
    /// Data the Watch sent.
    @ObservationIgnored public var onData: (([Data]) -> Void)?
    @ObservationIgnored private var session: HKWorkoutSession?

    /// Picks up mirrored workouts. Call once at launch, before the Watch might start one.
    public func activate() {
        guard let store = HealthBridge.shared.store else { return }
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.attach(session) }
        }
    }

    /// Asks the Watch to start a workout and mirror it here. Does nothing without a Watch.
    public func startWatchWorkout(activity: HKWorkoutActivityType = .traditionalStrengthTraining) async {
        guard let store = HealthBridge.shared.store, session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        configuration.locationType = .indoor
        try? await store.startWatchApp(toHandle: configuration)
    }

    /// Sends data to the Watch. Returns whether it got there: false with no mirrored workout or when
    /// HealthKit couldn't deliver it (the Watch out of reach), so a caller that hands the Watch a job,
    /// like saving the workout, can do the job itself instead.
    @discardableResult
    public func send(_ data: Data) async -> Bool {
        guard let session else { return false }
        do {
            try await session.sendToRemoteWorkoutSession(data: data)
            return true
        } catch {
            healthLog.error("Couldn't send to the Watch: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func attach(_ session: HKWorkoutSession) {
        self.session = session
        session.delegate = self
        isConnected = true
    }

    private func detach(_ source: HKWorkoutSession) {
        guard source === session else { return }
        session = nil
        isConnected = false
    }

    private func received(_ data: [Data], from source: HKWorkoutSession) {
        guard source === session else { return }
        onData?(data)
    }
}

extension WorkoutMirror: HKWorkoutSessionDelegate {
    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                           from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in self.detach(workoutSession) }
    }

    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {}

    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in self.received(data, from: workoutSession) }
    }

    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        Task { @MainActor in self.detach(workoutSession) }
    }
}
#endif
