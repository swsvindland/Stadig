import Foundation
import SystemCore

/// One hour of a day's log, with what was eaten in it, earliest first.
public struct HourGroup: Hashable, Sendable, Identifiable {
    /// The hour's first moment. This, not `hour`, tells two hours apart: when the clocks go back, a
    /// day has the same hour twice.
    public var start: Date
    /// Where the next hour starts.
    public var end: Date
    /// The hour on the clock, 0 to 23.
    public var hour: Int
    public var entries: [FoodEntry]

    public var id: Date { start }

    public init(start: Date, end: Date, hour: Int, entries: [FoodEntry] = []) {
        self.start = start
        self.end = end
        self.hour = hour
        self.entries = entries
    }
}

/// A day read hour by hour, the way the Log tab shows it. Entries keep their own minutes: this is
/// only how they're laid out, and ``Timeline/moments(_:gap:)`` still decides what a meal is.
public enum DayHours {
    /// The hour a day with no food opens on, near where most people's first meal goes.
    public static let emptyDayHour = 7

    /// Every hour of a day, eaten in or not: 24, or 23 or 25 on the days the clocks change. An entry
    /// outside the day, as one logged in another time zone can be, goes in the nearest hour rather
    /// than off the list.
    public static func groups(on day: Day, entries: [FoodEntry], calendar: Calendar = .current) -> [HourGroup] {
        let end = day.adding(days: 1).date(calendar: calendar)
        var groups: [HourGroup] = []
        var moment = day.date(calendar: calendar)
        while moment < end {
            let clock = calendar.dateComponents([.hour, .minute, .second], from: moment)
            // To the next hour on the clock, which isn't an hour on where a change moves it by half of one.
            let past = (clock.minute ?? 0) * 60 + (clock.second ?? 0)
            let next = min(moment.addingTimeInterval(TimeInterval(3600 - past)), end)
            groups.append(HourGroup(start: moment, end: next, hour: clock.hour ?? 0))
            moment = next
        }
        guard !groups.isEmpty else { return [] }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            let index = groups.lastIndex { $0.start <= entry.date } ?? 0
            groups[index].entries.append(entry)
        }
        return groups
    }

    /// The hour to open a day on: on today the hour it is now, on another day its first food's hour,
    /// else ``emptyDayHour``. It's an hour of `groups`, or nil when there are none.
    public static func opening(_ groups: [HourGroup], now: Date) -> HourGroup? {
        if let current = groups.first(where: { $0.start <= now && now < $0.end }) { return current }
        return groups.first { !$0.entries.isEmpty } ?? groups.first { $0.hour >= emptyDayHour } ?? groups.first
    }

    /// When a + on an hour logs: now, in the hour it is now; just after the hour's last food, so it
    /// joins that meal; otherwise the top of the hour.
    public static func addTime(_ group: HourGroup, now: Date) -> Date {
        if group.start <= now && now < group.end { return now }
        guard let last = group.entries.last else { return group.start }
        return min(last.date.addingTimeInterval(60), group.end.addingTimeInterval(-60))
    }
}
