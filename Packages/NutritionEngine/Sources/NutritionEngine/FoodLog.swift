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

    /// When the next meal is due in a fast begun at `start`: the first food still to come that's
    /// enough to end it (``LaterFood/marked(_:after:since:)``), not a coffee.
    public func nextMeal(since start: Date) -> Date? {
        LaterFood.marked(upcoming, after: eaten, since: start).first(where: \.isMeal)?.date
    }

    /// What's to come through a day, earliest first, for the widgets and complications. `start` is
    /// when the running fast began, if one is.
    public func later(through last: Day, since start: Date?) -> [LaterFood] { LaterFood.of(upcoming, after: eaten, since: start, through: last) }
}

extension LaterFood {
    /// `entries` through a day, earliest first. Past that the snapshot would only grow: a widget's
    /// timeline ends at midnight, and the app writes again long before the day after.
    public static func of(_ entries: [FoodEntry], after eaten: [FoodEntry], since start: Date?, through last: Day) -> [LaterFood] {
        marked(entries.filter { $0.day <= last }, after: eaten, since: start)
    }

    /// Food to come, earliest first, each marked a meal from the one that takes a run of food (each
    /// within ``Timeline/gap`` of the last) to ``MealTiming/mealKcal``. That's when ``Fasting/runs(_:entries:now:)``
    /// will find the meal, once they've happened: two small foods together end a fast, and food
    /// chained to the meal a fast began from doesn't. `eaten` can have begun the run; `start` is when
    /// the running fast began, if one is.
    static func marked(_ entries: [FoodEntry], after eaten: [FoodEntry], since start: Date?) -> [LaterFood] {
        let sorted = entries.sorted { $0.date < $1.date }
        guard let first = sorted.first?.date else { return [] }
        var run = FoodRun(start: start)
        // A day back is further than a run goes, and spares sorting years.
        for entry in eaten.filter({ $0.date > first.addingTimeInterval(-86_400) }).sorted(by: { $0.date < $1.date }) { run.add(entry) }
        run.leaveMealsEaten()
        return sorted.map { entry in
            run.add(entry)
            return LaterFood(date: entry.date, nutrients: entry.nutrients, isMeal: run.isMeal)
        }
    }
}

/// Food in date order, read as ``Fasting/runs(_:entries:now:)`` reads it: what's gone in since the last
/// gap of more than ``Timeline/gap``, counted from the start of the fast if there is one.
private struct FoodRun {
    let start: Date?
    var last: Date?
    /// What's gone in since the fast began, or in all without one.
    var kcal = 0.0
    /// What's gone in from before the fast began.
    var before = 0.0
    /// A meal from before the fast is running on past its start: a dessert, not a new meal.
    var runningOn = false

    mutating func add(_ entry: FoodEntry) {
        if let last, entry.date.timeIntervalSince(last) > Timeline.gap {
            kcal = 0
            before = 0
            runningOn = false
        }
        last = entry.date
        if let start, entry.date <= start {
            before += entry.nutrients.kcal
        } else {
            if before >= MealTiming.mealKcal { runningOn = true }
            kcal += entry.nutrients.kcal
        }
    }

    /// A meal already eaten doesn't make the mint after it another one.
    mutating func leaveMealsEaten() {
        if kcal >= MealTiming.mealKcal { kcal = 0 }
    }

    var isMeal: Bool { !runningOn && kcal >= MealTiming.mealKcal }
}
