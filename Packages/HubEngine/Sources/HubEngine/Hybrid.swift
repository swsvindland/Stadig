import Foundation
import SystemCore

/// A week split between the office and home. An office day is often shorter than the working day,
/// with the rest done at home on either side of it, and the commute falls between the two.
public struct HybridWeek: Hashable, Sendable {
    public enum Place: String, CaseIterable, Sendable, Identifiable {
        case office, home, off

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .office: "Office"
            case .home: "Home"
            case .off: "Off"
            }
        }
    }

    static let officeLabel = "Office"
    static let homeLabel = "Work at home"

    /// Seven days, Monday first.
    public var days: [Place]
    public var officeStart: Int
    public var officeEnd: Int
    /// Minutes worked at home on an office day, before leaving and after getting back.
    public var homeBefore: Int
    public var homeAfter: Int
    /// The hours of a day that's all at home.
    public var homeStart: Int
    public var homeEnd: Int

    public init(days: [Place], officeStart: Int, officeEnd: Int, homeBefore: Int, homeAfter: Int, homeStart: Int, homeEnd: Int) {
        self.days = days
        self.officeStart = officeStart
        self.officeEnd = officeEnd
        self.homeBefore = homeBefore
        self.homeAfter = homeAfter
        self.homeStart = homeStart
        self.homeEnd = homeEnd
    }

    /// Three days in, two at home: six hours at the office with an hour at home on either side.
    public static let standard = HybridWeek(
        days: [.office, .office, .office, .home, .home, .off, .off], officeStart: 9 * 60, officeEnd: 15 * 60, homeBefore: 60, homeAfter: 60,
        homeStart: 9 * 60, homeEnd: 17 * 60)

    /// Whether it can be a real week: nothing a model says gets past here unchecked.
    public var isValid: Bool {
        let times = [officeStart, homeStart]
        return days.count == 7 && times.allSatisfy { (0..<1440).contains($0) } && officeEnd > officeStart && homeEnd > homeStart
            && officeEnd - officeStart + homeBefore + homeAfter <= 16 * 60 && homeEnd - homeStart <= 16 * 60 && homeBefore >= 0 && homeAfter >= 0
    }

    func spans(_ place: Place) -> [DaySpan] {
        switch place {
        case .off: return []
        case .home: return [DaySpan(.home, Self.homeLabel, from: homeStart, to: homeEnd)]
        case .office:
            var out: [DaySpan] = []
            if homeBefore > 0 { out.append(DaySpan(.home, Self.homeLabel, from: max(0, officeStart - homeBefore), to: officeStart)) }
            out.append(DaySpan(.work, Self.officeLabel, from: officeStart, to: officeEnd))
            if homeAfter > 0 { out.append(DaySpan(.home, Self.homeLabel, from: officeEnd, to: officeEnd + homeAfter)) }
            return out
        }
    }

    /// The commute goes in afterwards, and moves the hours at home out of its way.
    public func pattern(anchor: Day, commute: Int = 0) -> WorkPattern {
        WorkPattern(anchor: anchor, weeks: [days.map(spans)]).withCommute(commute)
    }

    /// Minutes of work in the week.
    public var weeklyMinutes: Int { days.flatMap(spans).map(\.minutes).reduce(0, +) }

    /// The week a pattern is, to open it for editing. Nil if it isn't one week of the same office and
    /// home days, in which case it's left to the day-by-day editor.
    public init?(_ pattern: WorkPattern) {
        guard pattern.weeks.count == 1, let week = pattern.weeks.first, week.count == 7, !pattern.isRoster, pattern.overrides.isEmpty else {
            return nil
        }
        guard week.contains(where: { $0.contains { $0.kind == .home } }) else { return nil }
        self = .standard
        days = []
        var office: (start: Int, end: Int, before: Int, after: Int)?
        var home: (start: Int, end: Int)?
        for day in week {
            let spans = day.filter { $0.kind != .commute && $0.kind != .sleep }
            let away = spans.filter { $0.kind != .home }
            let homes = spans.filter { $0.kind == .home }
            if spans.isEmpty {
                days.append(.off)
            } else if let first = away.first {
                guard away.count == 1 else { return nil }
                let shape = (
                    start: first.start, end: first.end, before: homes.filter { $0.end <= first.start }.map(\.minutes).reduce(0, +),
                    after: homes.filter { $0.start >= first.end }.map(\.minutes).reduce(0, +)
                )
                if let office, office != shape { return nil }
                office = shape
                days.append(.office)
            } else {
                guard homes.count == 1 else { return nil }
                let shape = (start: homes[0].start, end: homes[0].end)
                if let home, home != shape { return nil }
                home = shape
                days.append(.home)
            }
        }
        if let office { (officeStart, officeEnd, homeBefore, homeAfter) = office }
        if let home { (homeStart, homeEnd) = home }
    }
}

extension ScheduleReader {
    /// Whether a sentence is about a week split between home and an office. These go to their own
    /// reading, or to the model: read as a plain day, "8 hours" would hide everything else it said.
    static func isHybrid(_ text: String) -> Bool {
        ["hybrid", "from home", "at home", "remote", "wfh", "in the office", "in office", "at the office", "on site", "onsite"]
            .contains { text.contains($0) }
    }

    /// The weekdays a piece of a sentence names, Monday being 0: each one, or a range.
    static func named(in text: String) -> [Int] {
        let names = "(mon|tue|wed|thu|fri|sat|sun)[a-z]*"
        if let regex = try? Regex("\(names)\\s*(?:to|through|thru|-|–)\\s*\(names)"), text.firstMatch(of: regex) != nil {
            return Array(days(in: text))
        }
        guard let regex = try? Regex("\\b\(names)") else { return [] }
        let found = text.matches(of: regex).compactMap { $0[1].substring.flatMap { weekdays.firstIndex(of: String($0)) } }
        return Array(Set(found)).sorted()
    }

    /// Numbers in words as digits, and "an hour" as "1 hour", so one pattern reads both.
    static func digits(_ text: String) -> String {
        var out = " " + text.replacingOccurrences(of: ",", with: " , ").replacingOccurrences(of: ".", with: " , ") + " "
        for (index, word) in ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"].enumerated() {
            out = out.replacingOccurrences(of: " \(word) ", with: " \(index + 1) ")
        }
        return out.replacingOccurrences(of: " an hour", with: " 1 hour").replacingOccurrences(of: " a hour", with: " 1 hour")
    }

    static func number(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? Regex(pattern) else { return nil }
        return text.firstMatch(of: regex).flatMap { $0[1].substring }.flatMap { Int($0) }
    }

    /// A hybrid week from a sentence. Nil when it says too little to be anyone's week in particular,
    /// which leaves it to the model.
    static func readHybrid(_ sentence: String, anchor: Day) -> Draft? {
        let text = digits(sentence)
        let clauses = text.split(separator: ",").map(String.init)
        func isOffice(_ clause: String) -> Bool { ["office", "on site", "onsite"].contains { clause.contains($0) } }
        func isHome(_ clause: String) -> Bool { ["home", "remote", "wfh"].contains { clause.contains($0) } }
        // A clause that names days and only one place. "the rest in the office" names none, and "Mon,
        // Wed and Fri in the office" spreads its days across clauses, so a list runs on to its place.
        var officeNamed: [Int] = []
        var homeNamed: [Int] = []
        var waiting: [Int] = []
        for clause in clauses {
            let days = named(in: clause)
            if isOffice(clause) && !isHome(clause) {
                officeNamed += waiting + days
                waiting = []
            } else if isHome(clause) && !isOffice(clause) {
                homeNamed += waiting + days
                waiting = []
            } else {
                waiting += days
            }
        }
        let officeCount = number(#"(\d)\s*days?(?:\s+a\s+week)?\s+(?:in|at|on)\b[^,]*(?:office|site)"#, in: text)
        let homeCount = number(#"(\d)\s*days?(?:\s+a\s+week)?\s+(?:at|from|in)\b[^,]*home"#, in: text)
        let officeLength = number(#"office[^,]*?(\d{1,2})\s*hours?"#, in: text) ?? number(#"(\d{1,2})\s*hours?[^,]*office"#, in: text)
        let before = number(#"(\d)\s*hours?(?:\s+[a-z]+){0,3}?\s+before"#, in: text)
        let after = number(#"(\d)\s*hours?(?:\s+[a-z]+){0,3}?\s+after"#, in: text) ?? number(#"(\d)\s*hours?\s+before\s+and\s+after"#, in: text)
        let span = times(in: text)
        guard !officeNamed.isEmpty || !homeNamed.isEmpty || officeCount != nil || homeCount != nil || officeLength != nil || span != nil else {
            return nil
        }

        var week = HybridWeek.standard
        // Named days win; a count takes days from the start of the week, for the person to move.
        var office = Set(officeNamed)
        var home = Set(homeNamed).subtracting(office)
        if office.isEmpty {
            let free = (0..<5).filter { !home.contains($0) }
            office = Set(free.prefix(officeCount ?? max(0, 5 - (homeCount ?? home.count))))
        }
        if home.isEmpty { home = Set((0..<5).filter { !office.contains($0) }.prefix(homeCount ?? 5)) }
        week.days = (0..<7).map { office.contains($0) ? .office : home.contains($0) ? .home : .off }

        if let span {
            week.officeStart = span.start
            week.officeEnd = span.end
        } else if let officeLength {
            week.officeEnd = week.officeStart + officeLength * 60
        }
        // What the sentence doesn't say makes up an eight-hour day, on the far side from what it does.
        let rest = max(0, 8 * 60 - (week.officeEnd - week.officeStart))
        switch (before, after) {
        case (let before?, let after?): (week.homeBefore, week.homeAfter) = (before * 60, after * 60)
        case (let before?, nil): (week.homeBefore, week.homeAfter) = (before * 60, max(0, rest - before * 60))
        case (nil, let after?): (week.homeBefore, week.homeAfter) = (max(0, rest - after * 60), after * 60)
        case (nil, nil): (week.homeBefore, week.homeAfter) = (rest / 2, rest - rest / 2)
        }
        return draft(week, anchor: anchor)
    }

    /// The hybrid week, if it can be one: the check every reading goes through.
    static func draft(_ week: HybridWeek, anchor: Day) -> Draft? {
        guard week.isValid, week.days.contains(.office) || week.days.contains(.home) else { return nil }
        return Draft(pattern: week.pattern(anchor: anchor), asksWhichWeek: false)
    }
}
