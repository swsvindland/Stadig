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
        /// When resting: when the rest began, so its ruler drains by itself toward the end. Nil from
        /// an app that didn't send it, whose ruler stays the session's.
        var restStartedAt: Date?
        /// The adjustment just made ("Easy, so the weight goes up.").
        var message: String?
        var progress: Double
    }

    var title: String
}
#endif
