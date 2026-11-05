import Foundation
import SystemCore

/// The usual shapes of a week, to start from.
public enum SchedulePreset: String, CaseIterable, Sendable, Identifiable {
    case nineToFive, alternateFridays, university, rotatingShifts, nothingFixed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .nineToFive: "9 to 5"
        case .alternateFridays: "Alternate Fridays"
        case .university: "University"
        case .rotatingShifts: "Shifts"
        case .nothingFixed: "Nothing fixed"
        }
    }

    /// The pattern, its cycle starting the week of `anchor`. For alternate Fridays, that's the week
    /// the Friday is worked.
    public func pattern(anchor: Day) -> WorkPattern {
        let nine = [DaySpan(.work, "Work", from: 9 * 60, to: 17 * 60)]
        let long = [DaySpan(.work, "Work", from: 8 * 60, to: 17 * 60 + 30)]
        let off: [DaySpan] = []
        switch self {
        case .nineToFive:
            return WorkPattern(anchor: anchor, weeks: [[nine, nine, nine, nine, nine, off, off]])
        case .alternateFridays:
            return WorkPattern(anchor: anchor, weeks: [[long, long, long, long, nine, off, off], [long, long, long, long, off, off, off]])
        case .university:
            func lecture(_ hour: Int, _ hours: Int = 1) -> DaySpan { DaySpan(.school, "Lecture", from: hour * 60, to: (hour + hours) * 60) }
            return WorkPattern(
                anchor: anchor,
                weeks: [[[lecture(10, 2)], [lecture(13), lecture(14, 2)], [lecture(10, 2)], [lecture(13, 2)], [lecture(10)], off, off]])
        case .rotatingShifts:
            let early = [DaySpan(.work, "Early shift", from: 6 * 60, to: 14 * 60)]
            let late = [DaySpan(.work, "Late shift", from: 14 * 60, to: 22 * 60)]
            return WorkPattern(anchor: anchor, weeks: [[early, early, early, off, late, late, off], [off, late, late, early, early, early, off]])
        case .nothingFixed:
            return WorkPattern(anchor: anchor, weeks: [[off, off, off, off, off, off, off]])
        }
    }
}

/// A schedule in words, for checking it's right.
public enum ScheduleSummary {
    /// "9 AM", "5:30 PM".
    public static func clock(_ minutes: Int) -> String {
        let total = ((minutes % 1440) + 1440) % 1440
        let hour = total / 60
        let display = hour % 12 == 0 ? 12 : hour % 12
        let minute = total % 60 == 0 ? "" : String(format: ":%02d", total % 60)
        return "\(display)\(minute) \(hour < 12 ? "AM" : "PM")"
    }

    public static func describe(_ spans: [DaySpan]) -> String {
        // The commute has a line of its own: these are the hours you're there.
        let awake = spans.filter { $0.kind != .sleep && $0.kind != .commute }
        guard let first = awake.min(by: { $0.start < $1.start }), let last = awake.max(by: { $0.end < $1.end }) else { return "off" }
        return "\(clock(first.start)) to \(clock(last.end))"
    }

    /// A line for each run of days that look the same, a block for each week of a cycle.
    public static func lines(_ pattern: WorkPattern) -> [String] {
        if pattern.isRoster { return ["Set week by week"] }
        var out: [String] = []
        for (index, week) in pattern.weeks.enumerated() {
            if pattern.weeks.count > 1 { out.append("Week \(index + 1)") }
            var start = 0
            while start < week.count {
                var end = start
                let text = describe(week[start])
                while end + 1 < week.count, describe(week[end + 1]) == text { end += 1 }
                let first = Weekday.allCases[start].short
                let days = start == end ? first : "\(first) to \(Weekday.allCases[end].short)"
                out.append("\(days): \(text)")
                start = end + 1
            }
        }
        if let endsOn = pattern.endsOn { out.append("Until \(endsOn.iso)") }
        return out
    }
}

/// Reads a schedule from a sentence with plain rules: the same result on every device, with or
/// without a model on it. What comes back is only ever a draft, for the person to check. Apple
/// Intelligence, where there is any, fills the same draft from what these rules can't read.
public enum ScheduleReader {
    /// What was read, and whether it still needs an answer before it can be used.
    public struct Draft: Hashable, Sendable {
        public var pattern: WorkPattern
        /// Alternating weeks: which of the next two Fridays is off has to be asked.
        public var asksWhichWeek: Bool
    }

    static let weekdays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    /// The weekdays a sentence names: a range, or "weekdays". Monday to Friday if it doesn't say.
    static func days(in text: String) -> ClosedRange<Int> {
        let names = "(mon|tue|wed|thu|fri|sat|sun)[a-z]*"
        if let regex = try? Regex("\(names)\\s*(?:to|through|thru|-|–)\\s*\(names)"), let match = text.firstMatch(of: regex),
            let from = (match[1].substring).flatMap({ weekdays.firstIndex(of: String($0)) }),
            let to = (match[2].substring).flatMap({ weekdays.firstIndex(of: String($0)) }), from <= to
        {
            return from...to
        }
        return 0...4
    }

    /// Hours from a sentence: "9 to 5", "8:30am-5pm", or "9 hours", which starts at eight with half
    /// an hour for lunch. Nil if it doesn't say.
    static func hours(in text: String) -> (start: Int, end: Int)? {
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:to|until|till|-|–)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        if let regex = try? Regex(pattern), let match = text.firstMatch(of: regex),
            let fromHour = match[1].substring.flatMap({ Int($0) }), let toHour = match[4].substring.flatMap({ Int($0) })
        {
            let fromMinute = match[2].substring.flatMap { Int($0) } ?? 0
            let toMinute = match[5].substring.flatMap { Int($0) } ?? 0
            func minutes(_ hour: Int, _ minute: Int, _ meridiem: Substring?) -> Int {
                var hour = hour
                if meridiem == "pm", hour < 12 { hour += 12 }
                if meridiem == "am", hour == 12 { hour = 0 }
                return hour * 60 + minute
            }
            let start = minutes(fromHour, fromMinute, match[3].substring)
            var end = minutes(toHour, toMinute, match[6].substring)
            // "9 to 5": the end comes after the start.
            while end <= start { end += 12 * 60 }
            return (start, end)
        }
        if let regex = try? Regex(#"(\d{1,2})[\s-]*hours?"#), let match = text.firstMatch(of: regex),
            let hours = match[1].substring.flatMap({ Int($0) }),
            (1...14).contains(hours)
        {
            return (8 * 60, 8 * 60 + hours * 60 + 30)
        }
        return nil
    }

    /// A draft from a sentence, or nil if the rules can't read it.
    public static func read(_ sentence: String, anchor: Day) -> Draft? {
        let text = sentence.lowercased()
        func any(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        if any("shift", "roster", "rota") { return Draft(pattern: SchedulePreset.rotatingShifts.pattern(anchor: anchor), asksWhichWeek: true) }
        if any("lecture", "university", "semester", "tutorial", "college") {
            return Draft(pattern: SchedulePreset.university.pattern(anchor: anchor), asksWhichWeek: false)
        }
        let span = hours(in: text)
        let alternating = any("every other friday", "alternate friday", "other friday", "second friday")
        guard span != nil || alternating else { return nil }
        return draft(days: days(in: text), start: span?.start ?? 9 * 60, end: span?.end ?? 17 * 60, alternatingFridays: alternating, anchor: anchor)
    }

    /// The hours on the days given, Monday being 0, with every second Friday off if that's asked. Nil
    /// for what can't be a working day, so nothing a model says can get past here unchecked.
    static func draft(days: ClosedRange<Int>, start: Int, end: Int, alternatingFridays: Bool, anchor: Day) -> Draft? {
        guard days.lowerBound >= 0, days.upperBound <= 6, start >= 0, start < 1440, end > start, end - start <= 16 * 60 else { return nil }
        let day = [DaySpan(.work, "Work", from: start, to: end)]
        var week: [[DaySpan]] = (0..<7).map { days.contains($0) ? day : [] }
        guard alternatingFridays else { return Draft(pattern: WorkPattern(anchor: anchor, weeks: [week]), asksWhichWeek: false) }
        // Monday to Thursday are as said; Friday is a plain eight hours one week and off the next.
        for index in 0..<4 { week[index] = day }
        week[4] = [DaySpan(.work, "Work", from: 9 * 60, to: 17 * 60)]
        var other = week
        other[4] = []
        return Draft(pattern: WorkPattern(anchor: anchor, weeks: [week, other]), asksWhichWeek: true)
    }
}
