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
