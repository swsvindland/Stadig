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

    /// Whether `all` is in date order, so a split or an insert can use it.
    private let isSorted: Bool

    /// How far past a moment a food still counts as having happened. The store keeps dates to the
    /// millisecond, rounded, so a food logged this instant can come back a fraction ahead of the
    /// clock, and it shouldn't be later food for that fraction.
    static let tolerance: TimeInterval = 0.001

    /// The last date that counts as having happened by `now`.
    private static func latest(by now: Date) -> Date { now.addingTimeInterval(tolerance) }

    public init(_ entries: [FoodEntry], now: Date) {
        all = entries
        self.now = now
        isSorted = false
        let latest = Self.latest(by: now)
        // Nearly always nothing's upcoming: then there's nothing to copy.
        if entries.contains(where: { $0.date > latest }) {
            eaten = entries.filter { $0.date <= latest }
            upcoming = entries.filter { $0.date > latest }
        } else {
            eaten = entries
            upcoming = []
        }
    }

    /// A log of entries already in date order, which splits without walking them.
    public init(sorted entries: [FoodEntry], now: Date) {
        all = entries
        self.now = now
        isSorted = true
        let split = Self.firstIndex(in: entries, after: Self.latest(by: now))
        if split == entries.count {
            eaten = entries
            upcoming = []
        } else {
            eaten = Array(entries[..<split])
            upcoming = Array(entries[split...])
        }
    }

    /// The first entry dated after `date`, in entries in date order.
    private static func firstIndex(in entries: [FoodEntry], after date: Date) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let middle = (low + high) / 2
            if entries[middle].date <= date { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// This log with new entries in their places. What a save of new food costs, rather than a sort
    /// of years of it, on a log in date order; any other is split afresh.
    public func inserting(_ new: [FoodEntry], now: Date) -> FoodLog {
        guard isSorted else { return FoodLog(all + new, now: now) }
        var all = all
        for entry in new { all.insert(entry, at: Self.firstIndex(in: all, after: entry.date)) }
        return FoodLog(sorted: all, now: now)
    }

    /// When the next food's time comes, and with it the next change to `eaten`.
    public var nextChange: Date? { upcoming.map(\.date).min() }

    /// Whether a food's time has passed since this split.
    public func isStale(at now: Date) -> Bool { nextChange.map { $0 <= now } ?? false }

    /// The same log split at another moment.
    public func at(_ now: Date) -> FoodLog { isSorted ? FoodLog(sorted: all, now: now) : FoodLog(all, now: now) }

    public func isUpcoming(_ entry: FoodEntry) -> Bool { entry.date > Self.latest(by: now) }

    /// When the next meal is due: food enough to end a fast (``MealTiming/mealKcal``), not a coffee.
    public var nextMeal: Date? { upcoming.filter { $0.nutrients.kcal >= MealTiming.mealKcal }.map(\.date).min() }

    /// What's to come through a day, earliest first, for the widgets and complications.
    public func later(through last: Day) -> [LaterFood] { LaterFood.of(upcoming, through: last) }
}

extension LaterFood {
    /// `entries` through a day, earliest first. Past that the snapshot would only grow: a widget's
    /// timeline ends at midnight, and the app writes again long before the day after.
    public static func of(_ entries: [FoodEntry], through last: Day) -> [LaterFood] {
        entries.filter { $0.day <= last }.sorted { $0.date < $1.date }.map {
            LaterFood(date: $0.date, nutrients: $0.nutrients, isMeal: $0.nutrients.kcal >= MealTiming.mealKcal)
        }
    }
}
