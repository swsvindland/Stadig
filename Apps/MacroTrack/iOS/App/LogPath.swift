import Foundation
import OSLog

/// Intervals along the path from a tap to fresh numbers: logging a food and changing day. They show
/// in Instruments under Points of Interest, and in DEBUG builds `LogPathBenchmarkTests` hears them.
enum LogPath {
    private static let signposter = OSSignposter(subsystem: "dev.svindland.stadig.macro", category: .pointsOfInterest)

    #if DEBUG
    /// Told of each interval as it ends, so a test can report the steps without Instruments.
    static var onInterval: ((String, Duration) -> Void)?
    #endif

    struct Interval {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
        #if DEBUG
        fileprivate let start = ContinuousClock.now
        #endif
    }

    /// Starts an interval; `end` it with a `defer` on the next line, so every return is covered.
    static func begin(_ name: StaticString) -> Interval {
        Interval(name: name, state: signposter.beginInterval(name))
    }

    static func end(_ interval: Interval) {
        signposter.endInterval(interval.name, interval.state)
        #if DEBUG
        onInterval?("\(interval.name)", ContinuousClock.now - interval.start)
        #endif
    }
}

/// Wakes the model when what's been eaten can change: at the time of the next food logged for
/// later, and when the day, the clock or the time zone does. Going with its owner, it stops all of it.
nonisolated final class FoodClock {
    private let fire: @MainActor @Sendable () -> Void
    private var observers: [NSObjectProtocol] = []
    private var wake: Task<Void, Never>?

    init(fire: @escaping @MainActor @Sendable () -> Void) {
        self.fire = fire
        let center = NotificationCenter.default
        observers = [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { fire() }
            }
        }
    }

    /// One timer for the date given, in place of any before it; nil leaves none.
    func arm(for date: Date?) {
        wake?.cancel()
        wake = nil
        guard let date else { return }
        let fire = fire
        wake = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            fire()
        }
    }

    deinit {
        wake?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
