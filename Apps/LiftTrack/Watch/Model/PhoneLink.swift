import Foundation
import LiftEngine
import WatchConnectivity

/// The Watch side of WatchConnectivity. The phone keeps today's context in the application
/// context; finished sessions go back both live (when the phone is reachable) and queued, and the
/// phone saves by id, so sending one twice is harmless. Each record waits in an outbox on disk
/// until its queued transfer has finished, so none is lost to an early quit or a failed transfer.
/// A request for a context goes the same two ways, and again on each delivery until one newer
/// than the request arrives.
@MainActor
final class PhoneLink: NSObject {
    static let shared = PhoneLink()

    /// Called with each context that arrives.
    var onContext: ((PhoneContext) -> Void)?
    /// Called with what the phone says about a session it leads, when it comes this way rather than
    /// over the mirrored workout.
    var onMirror: (([Data]) -> Void)?

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    /// When a context was asked for, until one sent after it arrives.
    private var contextRequested: Date?
    private static let kind = "kind"
    private static let contextRequest = "requestContext"

    func activate() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// Asks the phone to send a fresh context, now if it's reachable or when it next wakes.
    func requestContext() {
        contextRequested = Date()
        deliver()
    }

    /// Sends a finished session to the phone.
    func send(_ record: SessionRecord) {
        // Written back below: an outbox that's there but can't be read is moved aside first, rather
        // than written over with the sessions still waiting in it.
        var outbox = WatchStorage.load([SessionRecord].self, from: WatchStorage.outbox, settingAsideUnreadable: true) ?? []
        outbox.removeAll { $0.id == record.id }
        outbox.append(record)
        self.outbox = outbox
        deliver()
    }

    /// A message about the session the phone leads, while the phone is reachable: the second route
    /// beside the mirrored workout. Nothing is queued: a late one is no use.
    func sendLive(_ data: Data) {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["mirror": data], replyHandler: nil, errorHandler: Self.ignore)
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
        if contextRequested != nil, let data = try? WatchJSON.encoder().encode(LinkMessage.requestContext) {
            if session.isReachable { session.sendMessage(["m": data], replyHandler: nil, errorHandler: Self.ignore) }
            // One queued copy covers a live message the phone never answered.
            if !session.outstandingUserInfoTransfers.contains(where: { $0.userInfo[Self.kind] as? String == Self.contextRequest }) {
                session.transferUserInfo(["m": data, Self.kind: Self.contextRequest])
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
        var outbox = self.outbox
        // Only a list that holds it is written back: one that couldn't be read mustn't be emptied.
        guard outbox.contains(where: { $0.id.uuidString == id }) else { return }
        outbox.removeAll { $0.id.uuidString == id }
        self.outbox = outbox
    }

    /// WatchConnectivity calls error handlers on its own queue, so this one must not be main-actor
    /// isolated (a closure written here would be, and would trap). The queued copies of records and
    /// context requests cover failures.
    nonisolated private static func ignore(_ error: any Error) {}

    private func received(_ data: Data) {
        // Compressed by builds since the context carried the session after today's; plain before.
        guard let context = LinkData.decode(PhoneContext.self, from: data, with: WatchJSON.decoder()) else { return }
        if let asked = contextRequested, context.sentAt >= asked { answered() }
        onContext?(context)
    }

    /// The phone has sent a context since it was asked: no need to keep asking.
    private func answered() {
        contextRequested = nil
        for transfer in session?.outstandingUserInfoTransfers ?? [] where transfer.userInfo[Self.kind] as? String == Self.contextRequest {
            transfer.cancel()
        }
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

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["mirror"] as? Data else { return }
        Task { @MainActor in self.onMirror?([data]) }
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
