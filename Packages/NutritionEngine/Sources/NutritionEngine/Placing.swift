import Foundation
import SystemCore

/// Where foods land when they're moved or copied.
public enum Placement: Hashable, Sendable {
    /// From a moment on, keeping the gaps between them: to now, or to an hour.
    case starting(Date)
    /// On a day, each at its own time of day: to today, to tomorrow, to chosen dates.
    case sameTimes(on: Day)
}

public enum Placing {
    /// The dates for `entries` at a placement, in the order given. They stay inside the target day:
    /// foods that fit keep their spacing, and ones that don't go in order a minute apart, starting
    /// early enough that the last one still lands on the day.
    public static func dates(for entries: [FoodEntry], _ placement: Placement, calendar: Calendar = .current) -> [Date] {
        guard let earliest = entries.map(\.date).min() else { return [] }
        switch placement {
        case .sameTimes(let day):
            return entries.map { day.at(sameTimeAs: $0.date, calendar: calendar) }
        case .starting(let start):
            let spaced = entries.map { start.addingTimeInterval($0.date.timeIntervalSince(earliest)) }
            let day = Day(start, calendar: calendar)
            let end = day.adding(days: 1).date(calendar: calendar)
            if let latest = spaced.max(), latest < end { return spaced }
            // Past the end of the day: in order, a minute apart, moved back just far enough to fit.
            let order = entries.indices.sorted { entries[$0].date < entries[$1].date }
            let span = TimeInterval(entries.count) * 60
            let first = max(min(start, end.addingTimeInterval(-span)), day.date(calendar: calendar))
            var dates = spaced
            for (place, index) in order.enumerated() { dates[index] = first.addingTimeInterval(TimeInterval(place) * 60) }
            return dates
        }
    }
}
