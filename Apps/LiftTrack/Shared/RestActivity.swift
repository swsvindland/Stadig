#if os(iOS)
import ActivityKit
import Foundation

/// The session on the Lock Screen and in the Dynamic Island: the rest countdown, or the next set.
nonisolated struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// The exercise up next, and its set ("Set 2 of 3 · 122.5 kg × 7").
        var exercise: String
        var detail: String
        /// When resting: when the rest ends.
        var restEndsAt: Date?
        /// The adjustment just made ("Easy, so the weight goes up.").
        var message: String?
        var progress: Double
    }

    var title: String
}
#endif
