import Foundation
import SystemCore

/// Where foods land when they're moved or copied.
public enum Placement: Hashable, Sendable {
    /// From a moment on, keeping the gaps between them: to now, or to an hour.
    case starting(Date)
    /// On a day, each at its own time of day: to today, to tomorrow, to chosen dates.
    case sameTimes(on: Day)
    /// A meal eaten now, in order, ending at this moment.
    case now(Date)
}

public enum Placing {
    /// The dates for `entries` at a placement, in the order given. They stay inside the target day:
    /// foods that fit keep their spacing, and ones that don't go in order a minute apart, starting
    /// early enough that the last one still lands on the day. To now, just after midnight, they go
    /// closer than a second apart rather than back into yesterday.
    public static func dates(for entries: [FoodEntry], _ placement: Placement, calendar: Calendar = .current) -> [Date] {
        guard let earliest = entries.map(\.date).min() else { return [] }
        switch placement {
        case .sameTimes(let day):
            return entries.map { day.at(sameTimeAs: $0.date, calendar: calendar) }
        case .now(let now):
            // A second apart, as a meal's foods go in: not an hour's gaps running on into the future.
            let order = entries.indices.sorted { entries[$0].date < entries[$1].date }
            let midnight = Day(now, calendar: calendar).date(calendar: calendar)
            let gap = order.count > 1 ? min(1, now.timeIntervalSince(midnight) / TimeInterval(order.count - 1)) : 0
            var dates = entries.map(\.date)
            for (place, index) in order.enumerated() {
                dates[index] = max(midnight, now.addingTimeInterval(TimeInterval(place - order.count + 1) * gap))
            }
            return dates
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
