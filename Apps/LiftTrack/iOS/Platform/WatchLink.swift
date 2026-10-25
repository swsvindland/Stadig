#if os(iOS)
import ExerciseLibrary
import Foundation
import LiftEngine
import OSLog
import SystemCore
import SystemStore
import WatchConnectivity

/// The iPhone side of WatchConnectivity. The phone keeps the Watch's copy of today's session,
/// gym and history current in the application context, so the Watch can run the session on its
/// own. Finished Watch sessions come back both live and queued; saving is by id, so getting one
/// twice is harmless.
@MainActor
final class WatchLink: NSObject {
    static let shared = WatchLink()

    private var lastContext: Data?
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// A paired Watch with Stadig Lift on it.
    var watchAppInstalled: Bool {
        guard let session, session.activationState == .activated else { return false }
        return session.isPaired && session.isWatchAppInstalled
    }

    func publish(_ model: AppModel) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
            let context = Self.context(for: model)
        else { return }
        guard let data = try? SystemJSON.encoder().encode(context), data != lastContext else { return }
        lastContext = data
        var stamped = context
        stamped.sentAt = Date()
        guard let payload = try? SystemJSON.encoder().encode(stamped) else { return }
        do {
            // Compressed: two plans' history, and their swaps', runs to tens of kilobytes of JSON.
            try session.updateApplicationContext(["context": LinkData.compressed(payload)])
        } catch {
            appLog.error("Couldn't send the Watch today's plan: \(error.localizedDescription)")
        }
    }

    /// Today's plan and the one after it, with enough history for their exercises and likely swaps,
    /// stamped `.distantPast` so an unchanged context compares equal.
    static func context(for model: AppModel) -> PhoneContext? {
        guard let analysis = model.analysis else { return nil }
        let plan = model.plan()
        let following = model.followingPlan()
        let items = (plan?.items ?? []) + (following?.items ?? [])
        let exercises = Dictionary(items.map { ($0.exerciseID, $0) }, uniquingKeysWith: { first, _ in first })
        guard var context = model.watchContext(plan: plan, exercises: exercises, withSwaps: true) else { return nil }
        if let next = analysis.next, !next.scheduledToday {
            context.upNext =
                next.nextDay.map { "\(next.day.name) on \(Format.day($0, style: .dateTime.weekday(.wide)))" } ?? next.day.name
        }
        context.following = following
        context.sentAt = .distantPast
        return context
    }

    /// A message for the Watch app while it's reachable (during a workout it is): the second route
    /// beside the mirrored workout, for a session led from here.
    func sendLive(_ data: Data) {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["mirror": data], replyHandler: nil, errorHandler: Self.ignore)
    }

    /// WatchConnectivity calls error handlers on its own queue, so this one must not be main-actor
    /// isolated (a closure written here would be, and would trap). The other route covers a failure.
    nonisolated private static func ignore(_ error: any Error) {}

    fileprivate func handle(_ data: Data) {
        guard let message = try? SystemJSON.decoder().decode(LinkMessage.self, from: data) else { return }
        switch message {
        case .finished(let record):
            AppModel.shared.keep(record)
        case .requestContext:
            lastContext = nil
            // Woken in the background on a later day: today's plan, not the one from when it last ran.
            let model = AppModel.shared
            if model.today != .today { model.recompute() } else { publish(model) }
        }
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish(AppModel.shared) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message["mirror"] as? Data {
            // The Watch's half of a session led from here, by the second route: as if over the workout.
            Task { @MainActor in AppModel.shared.fromWatch([data]) }
            return
        }
        guard let data = message["m"] as? Data else { return }
        Task { @MainActor in self.handle(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["m"] as? Data else { return }
        Task { @MainActor in self.handle(data) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.lastContext = nil
            self.publish(AppModel.shared)
        }
    }
}
#endif
