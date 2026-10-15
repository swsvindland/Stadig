import Foundation

/// A calendar day with no time and no time zone. Schedules, adherence windows and life modes all
/// count in days, and a day must mean the same thing on every device and in every app.
public struct Day: Hashable, Comparable, Sendable, Strideable, CustomStringConvertible {
    /// Days since 1970-01-01 in the proleptic Gregorian calendar.
    public let ordinal: Int

    public init(ordinal: Int) { self.ordinal = ordinal }

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

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
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

    /// Midnight at the start of this day in the given calendar's time zone.
    public func date(calendar: Calendar = .current) -> Date {
        let c = components
        return calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? Date(timeIntervalSince1970: 0)
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

    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
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
