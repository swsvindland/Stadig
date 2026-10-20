#if os(iOS)
import ActivityKit
import Foundation

/// The running fast on the Lock Screen and in the Dynamic Island: how long, the phase, the goal.
nonisolated struct FastActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var start: Date
        var goalEnd: Date
        var phase: String
        var symbol: String
        /// The next phase and when it begins; nil in the last one.
        var nextPhase: String?
        var nextPhaseAt: Date?
    }

    /// The fast it shows.
    var id: UUID
}
#endif
