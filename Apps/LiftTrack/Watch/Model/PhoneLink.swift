import Foundation
import WatchConnectivity
import LiftEngine

/// The Watch side of WatchConnectivity. The phone keeps today's context in the application
/// context; finished sessions go back both live (when the phone is reachable) and queued, and the
/// phone saves by id, so sending one twice is harmless. Each record waits in an outbox on disk
/// until its queued transfer has finished, so none is lost to an early quit or a failed transfer.
@MainActor
final class PhoneLink: NSObject {
    static let shared = PhoneLink()

    /// Called with each context that arrives.
    var onContext: ((PhoneContext) -> Void)?

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var wantsContext = false

    func activate() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// Asks the phone to send a fresh context, now if it's reachable or when it next wakes.
    func requestContext() {
        wantsContext = true
        deliver()
    }

    /// Sends a finished session to the phone.
    func send(_ record: SessionRecord) {
        var outbox = self.outbox
        outbox.removeAll { $0.id == record.id }
        outbox.append(record)
        self.outbox = outbox
        deliver()
    }

    /// Waits while WatchConnectivity hands over queued content, for the background task that woke the app.
    func drain() async {
        activate()
        for _ in 0..<50 {
            guard let session, session.activationState != .activated || session.hasContentPending else { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: Delivery

    private var outbox: [SessionRecord] {
        get { WatchStorage.load([SessionRecord].self, from: WatchStorage.outbox) ?? [] }
        set {
            if newValue.isEmpty { WatchStorage.remove(WatchStorage.outbox) } else { WatchStorage.save(newValue, to: WatchStorage.outbox) }
        }
    }

    private func deliver() {
        guard let session, session.activationState == .activated else { return }
        if wantsContext, let data = try? WatchJSON.encoder().encode(LinkMessage.requestContext) {
            wantsContext = false
            if session.isReachable {
                session.sendMessage(["m": data], replyHandler: nil, errorHandler: Self.ignore)
            } else {
                session.transferUserInfo(["m": data])
            }
        }
        let queued = Set(session.outstandingUserInfoTransfers.compactMap { $0.userInfo["id"] as? String })
        for record in outbox where !queued.contains(record.id.uuidString) {
            guard let data = try? WatchJSON.encoder().encode(LinkMessage.finished(record)) else { continue }
            if session.isReachable { session.sendMessage(["m": data], replyHandler: nil, errorHandler: Self.ignore) }
            // Queued delivery survives the phone being away and this app quitting.
            session.transferUserInfo(["m": data, "id": record.id.uuidString])
        }
    }

    private func delivered(_ id: String) {
        outbox = outbox.filter { $0.id.uuidString != id }
    }

    /// WatchConnectivity calls error handlers on its own queue, so this one must not be main-actor
    /// isolated (a closure written here would be, and would trap). The queued copy covers failures.
    nonisolated private static func ignore(_ error: any Error) {}

    private func received(_ data: Data) {
        guard let context = try? WatchJSON.decoder().decode(PhoneContext.self, from: data) else { return }
        onContext?(context)
    }

    private func activated(context data: Data?) {
        if let data { received(data) }
        deliver()
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        let data = session.receivedApplicationContext["context"] as? Data
        Task { @MainActor in self.activated(context: data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["context"] as? Data else { return }
        Task { @MainActor in self.received(data) }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: (any Error)?) {
        // A failed transfer stays in the outbox and goes again on the next launch or reconnect.
        guard error == nil, let id = userInfoTransfer.userInfo["id"] as? String else { return }
        Task { @MainActor in self.delivered(id) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.deliver() }
    }
}
