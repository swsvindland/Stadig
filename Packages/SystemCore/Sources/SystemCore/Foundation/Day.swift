import Foundation

/// A calendar day with no time and no time zone. Schedules, adherence windows and life modes all
/// count in days, and a day must mean the same thing on every device and in every app.
public struct Day: Hashable, Comparable, Sendable, Strideable, CustomStringConvertible {
    /// Days since 1970-01-01 in the proleptic Gregorian calendar.
    public let ordinal: Int

    public init(ordinal: Int) { self.ordinal = ordinal }

    /// Further from 1970 than this, in days, a moment can't be a real date (about 2.7 million years).
    private static let ordinalLimit = 1e9

    public init(year: Int, month: Int, day: Int) {
        // Howard Hinnant's days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        ordinal = era * 146097 + doe - 719468
    }

    /// The day a moment falls on in the calendar's time zone. Only the time zone is used: a day is
    /// always a Gregorian date, so a phone set to the Buddhist, Japanese or Hebrew calendar still
    /// agrees with every other device on weekdays, ages and stored dates.
    public init(_ date: Date, calendar: Calendar = .current) {
        self.init(date, timeZone: calendar.timeZone)
    }

    public init(_ date: Date, timeZone: TimeZone) {
        // The wall-clock time there, in whole days since 1970. The offset is the one in force at that
        // moment, so daylight saving is accounted for.
        let local = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        let days = (local / 86_400).rounded(.down)
        // A corrupt timestamp (infinite, or past any real date) lands on 1970 rather than trapping
        // in the conversion to Int.
        self.init(ordinal: abs(days) < Day.ordinalLimit ? Int(days) : 0)
    }

    /// The day a moment counts for when days turn over at `hour` on the clock instead of at
    /// midnight: with days starting at 4, half past one on Saturday morning is still Friday. By the
    /// clock, so the night the clocks change still turns over at 4.
    public init(_ date: Date, dayStartsAt hour: Int, timeZone: TimeZone = .current) {
        let wallClock = date.addingTimeInterval(Double(timeZone.secondsFromGMT(for: date) - hour * 3600))
        self.init(wallClock, timeZone: .gmt)
    }

    public static var today: Day { Day(Date()) }

    public var components: (year: Int, month: Int, day: Int) {
        // civil_from_days.
        let z = ordinal + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    public var year: Int { components.year }
    public var month: Int { components.month }
    public var dayOfMonth: Int { components.day }

    /// Midnight at the start of this day in the given calendar's time zone (or the first moment of
    /// the day, where a clock change skips midnight). As with `init(_:calendar:)`, only the time zone
    /// is used.
    public func date(calendar: Calendar = .current) -> Date {
        let c = components
        let gregorian = calendar.identifier == .gregorian ? calendar : Day.gregorian(in: calendar.timeZone)
        return gregorian.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? Date(timeIntervalSince1970: 0)
    }

    public func date(timeZone: TimeZone) -> Date {
        date(calendar: Day.gregorian(in: timeZone))
    }

    /// This day at a time on the clock, in the time zone. By the clock, not midnight plus so many
    /// seconds, which is an hour off on the days the clocks change and can land on the next day. A
    /// day is a Gregorian date whatever calendar the phone shows, so the time is set in a Gregorian
    /// calendar. A time the clocks skip comes out just after the change: 02:30 on the night they go
    /// forward is 03:30.
    public func at(hour: Int, minute: Int, second: Int = 0, timeZone: TimeZone = .current) -> Date {
        let c = components
        let time = DateComponents(year: c.year, month: c.month, day: c.day, hour: hour, minute: minute, second: second)
        return Day.gregorian(in: timeZone).date(from: time) ?? date(timeZone: timeZone).addingTimeInterval(Double(hour * 3600 + minute * 60 + second))
    }

    /// `at(hour:minute:)` in the calendar's time zone. As with `init(_:calendar:)`, only the time
    /// zone is used.
    public func at(hour: Int, minute: Int, second: Int = 0, calendar: Calendar) -> Date {
        at(hour: hour, minute: minute, second: second, timeZone: calendar.timeZone)
    }

    /// `at(hour:minute:)` for minutes after midnight, the way dose and reminder times are kept.
    public func at(minutes: Int, timeZone: TimeZone = .current) -> Date {
        at(hour: minutes / 60, minute: minutes % 60, timeZone: timeZone)
    }

    public func at(minutes: Int, calendar: Calendar) -> Date { at(minutes: minutes, timeZone: calendar.timeZone) }

    /// This day at the time of day `time` shows on the clock in the time zone.
    public func at(sameTimeAs time: Date, timeZone: TimeZone = .current) -> Date {
        let c = Day.gregorian(in: timeZone).dateComponents([.hour, .minute, .second], from: time)
        return at(hour: c.hour ?? 12, minute: c.minute ?? 0, second: c.second ?? 0, timeZone: timeZone)
    }

    public func at(sameTimeAs time: Date, calendar: Calendar) -> Date { at(sameTimeAs: time, timeZone: calendar.timeZone) }

    private static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public var weekday: Weekday {
        // 1970-01-01 was a Thursday.
        let index = ((ordinal % 7) + 7 + 3) % 7
        return Weekday.allCases[index]
    }

    /// The Monday that starts this day's week.
    public var startOfWeek: Day { adding(days: -(weekday.rawValue - 1)) }

    public func adding(days: Int) -> Day { Day(ordinal: ordinal + days) }
    public func adding(weeks: Int) -> Day { adding(days: weeks * 7) }
    public func days(until other: Day) -> Int { other.ordinal - ordinal }

    public func distance(to other: Day) -> Int { other.ordinal - ordinal }
    public func advanced(by n: Int) -> Day { adding(days: n) }

    public static func < (a: Day, b: Day) -> Bool { a.ordinal < b.ordinal }

    /// "2026-10-15".
    public var iso: String {
        let c = components
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }

    /// Nil unless it's a real yyyy-mm-dd date: "2026-02-30" or "2026-x-10-18" would otherwise land on
    /// some other day.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2] else { return nil }
        // Bounded before the arithmetic, which would overflow and trap on a corrupt "2026-01-9223372036854775807".
        guard (0...999_999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let parsed = Day(year: year, month: month, day: day)
        guard parsed.components == (year, month, day) else { return nil }
        self = parsed
    }

    public var description: String { iso }
}

extension Day: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = Day(iso: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a yyyy-mm-dd day: \(text)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}

public enum Weekday: Int, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public var id: Int { rawValue }

    public var short: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    public var name: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    public static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }
}

/// An inclusive run of days.
public struct DayRange: Hashable, Codable, Sendable {
    public var start: Day
    public var end: Day

    public init(_ start: Day, _ end: Day) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public func contains(_ day: Day) -> Bool { day >= start && day <= end }
    public var count: Int { start.days(until: end) + 1 }
    public var days: [Day] { Array(stride(from: start, through: end, by: 1)) }

    public func overlaps(_ other: DayRange) -> Bool { start <= other.end && other.start <= end }

    public func clamped(to other: DayRange) -> DayRange? {
        guard overlaps(other) else { return nil }
        return DayRange(max(start, other.start), min(end, other.end))
    }
}
