import Foundation

/// A NotificationCenter block observer that's removed when this is released, so keeping it in its
/// owner ends the observation with the owner.
nonisolated final class NotificationToken {
    private let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol) { self.token = token }

    deinit { NotificationCenter.default.removeObserver(token) }

    /// Calls `handler` on the main actor each time `name` is posted.
    @MainActor
    static func observe(_ name: Notification.Name, _ handler: @escaping @MainActor @Sendable () -> Void) -> NotificationToken {
        NotificationToken(
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            })
    }
}
