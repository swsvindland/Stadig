import Foundation
import WatchConnectivity
import ExerciseLibrary
import LiftEngine
import SystemCore
import SystemStore

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

    func publish(_ model: AppModel) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let analysis = model.analysis, let profile = model.profile else { return }
        let plan = model.plan()
        var upNext: String?
        if let next = analysis.next, !next.scheduledToday {
            upNext = next.nextDay.map { "\(next.day.name) on \(Format.day($0, style: .dateTime.weekday(.wide)))" } ?? next.day.name
        }
        // Enough history for the plan's exercises and their likely swaps.
        var ids = Set(plan?.items.map(\.exerciseID) ?? [])
        for id in ids {
            let exercise = model.catalog.resolve(id)
            for option in Substitutions.candidates(for: exercise, in: model.catalog.all, availability: model.gym.availability, limit: 4) {
                ids.insert(option.id)
            }
        }
        var history: [String: [LoggedSet]] = [:]
        for id in ids {
            let sets = analysis.history[id] ?? []
            let days = Array(Set(sets.map { Day($0.date) })).sorted().suffix(4)
            history[id] = sets.filter { days.contains(Day($0.date)) }
        }
        let zones = HeartRateZones.estimated(age: profile.age(), resting: model.restingHeartRate)
        let context = PhoneContext(plan: plan, upNext: upNext, gym: model.gymForToday, trust: analysis.trust, phase: analysis.phase.effects,
                                   bodyweightKg: model.state?.effectiveBodyweight, history: history,
                                   enduranceScore: analysis.endurance.score, heartRateGuidedRest: model.settings.heartRateGuidedRest,
                                   zones: zones, units: profile.units, sentAt: .distantPast)
        guard let data = try? SystemJSON.encoder().encode(context), data != lastContext else { return }
        lastContext = data
        var stamped = context
        stamped.sentAt = Date()
        guard let payload = try? SystemJSON.encoder().encode(stamped) else { return }
        try? session.updateApplicationContext(["context": payload])
    }

    fileprivate func handle(_ data: Data) {
        guard let message = try? SystemJSON.decoder().decode(LinkMessage.self, from: data) else { return }
        switch message {
        case .finished(let record):
            AppModel.shared.keep(record)
        case .requestContext:
            lastContext = nil
            publish(AppModel.shared)
        }
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish(AppModel.shared) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
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
