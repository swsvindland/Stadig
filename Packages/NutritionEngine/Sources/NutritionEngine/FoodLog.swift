import Foundation
import SystemCore

/// The log split at a moment. Food with a date ahead of that moment is an ordinary entry that
/// hasn't happened yet: it counts for nothing until its time, and then it counts like any other,
/// whether or not it was eaten, unless it's been removed.
public struct FoodLog: Hashable, Sendable {
    /// Every entry, as given.
    public private(set) var all: [FoodEntry]
    /// The moment it's split at.
    public private(set) var now: Date
    /// Food whose time has come, in the order given.
    public private(set) var eaten: [FoodEntry]
    /// Food still to come, in the order given.
    public private(set) var upcoming: [FoodEntry]

    public init(_ entries: [FoodEntry], now: Date) {
        all = entries
        self.now = now
        // Nearly always nothing's upcoming: then there's nothing to copy.
        if entries.contains(where: { $0.date > now }) {
            eaten = entries.filter { $0.date <= now }
            upcoming = entries.filter { $0.date > now }
        } else {
            eaten = entries
            upcoming = []
        }
    }

    /// When the next food's time comes, and with it the next change to `eaten`.
    public var nextChange: Date? { upcoming.map(\.date).min() }

    /// Whether a food's time has passed since this split.
    public func isStale(at now: Date) -> Bool { nextChange.map { $0 <= now } ?? false }

    /// The same log split at another moment.
    public func at(_ now: Date) -> FoodLog { FoodLog(all, now: now) }

    public func isUpcoming(_ entry: FoodEntry) -> Bool { entry.date > now }
}
