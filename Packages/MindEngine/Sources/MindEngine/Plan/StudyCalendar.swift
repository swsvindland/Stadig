import Foundation
import SystemCore

/// Where someone is in the study calendar on a day.
public enum StudyPhase: Hashable, Sendable {
    /// The first two weeks: finding a level in each domain.
    case assessment(day: Int, of: Int)
    /// A normal week of a block (zero-based).
    case loading(week: Int, of: Int)
    /// The system-wide deload: review only, nothing new.
    case review(endsOn: Day)
    /// Vacation, illness or crunch mode: nothing expected.
    case paused(LifeModeKind)

    public var label: String {
        switch self {
        case .assessment(let day, let of): "Finding your level · day \(min(day, of)) of \(of)"
        case .loading(let week, let of): "Week \(week + 1) of \(of)"
        case .review: "Review week"
        case .paused(let kind): kind.label
        }
    }

    public var isReview: Bool { if case .review = self { true } else { false } }
    public var isPaused: Bool { if case .paused = self { true } else { false } }
    public var isAssessment: Bool { if case .assessment = self { true } else { false } }
}

/// The study calendar. With Lift Track installed, review weeks are the system deloads it
/// publishes; on its own, Mind Track runs five weeks then a review week.
public enum StudyCalendar {
    public static let assessmentDays = 14
    public static let loadingWeeks = 5

    public static func phase(on day: Day, start: Day, calendar: SystemCalendar?, lifeModes: [LifeModePeriod]) -> StudyPhase {
        if let paused = pause(on: day, lifeModes: lifeModes) { return .paused(paused) }
        let since = start.days(until: day)
        if since < assessmentDays { return .assessment(day: max(1, since + 1), of: assessmentDays) }
        if let calendar {
            if let deload = calendar.deloads.first(where: { $0.contains(day) }) { return .review(endsOn: deload.end) }
            if let block = calendar.currentBlock, block.contains(day) {
                let weeks = max(1, (block.count - 7 + 6) / 7)
                return .loading(week: min(weeks - 1, block.start.days(until: day) / 7), of: weeks)
            }
        }
        let cycle = since - assessmentDays
        let week = (cycle / 7) % (loadingWeeks + 1)
        if week == loadingWeeks {
            let blockStart = start.adding(days: assessmentDays + (cycle / 7 / (loadingWeeks + 1)) * (loadingWeeks + 1) * 7)
            return .review(endsOn: blockStart.adding(weeks: loadingWeeks + 1).adding(days: -1))
        }
        return .loading(week: week, of: loadingWeeks)
    }

    /// The next review week from `day` on (this one, if it's under way), within ten weeks.
    public static func nextReview(from day: Day, start: Day, calendar: SystemCalendar?) -> DayRange? {
        var first: Day?
        for offset in 0..<70 {
            let candidate = day.adding(days: offset)
            if case .review(let end) = phase(on: candidate, start: start, calendar: calendar, lifeModes: []) {
                first = first ?? candidate
                return DayRange(first!, end)
            }
        }
        return nil
    }

    /// Vacation, illness and crunch mode pause Mind Track (a five-minute review is offered in
    /// crunch, never expected). An injury doesn't touch study.
    public static func pause(on day: Day, lifeModes: [LifeModePeriod]) -> LifeModeKind? {
        for period in lifeModes where period.contains(day) && !period.isDeleted {
            switch period.kind {
            case .vacation, .illness, .crunch: return period.kind
            case .injury: continue
            }
        }
        return nil
    }

    /// Check-ins land at the end of a review week, when fresh, or in the first days after it if
    /// those were missed; and not twice.
    public static func checkInDue(
        on day: Day, start: Day, calendar: SystemCalendar?, lifeModes: [LifeModePeriod],
        lastCheckIn: Day?
    ) -> Bool {
        let phase = phase(on: day, start: start, calendar: calendar, lifeModes: lifeModes)
        let recent = lastCheckIn.map { $0.days(until: day) < 14 } ?? false
        guard !recent else { return false }
        switch phase {
        case .review(let end): return day.days(until: end) <= 2
        case .loading(let week, _): return week == 0 && start.days(until: day) >= assessmentDays + 7
        default: return false
        }
    }
}

/// The weekly split: Focus courses rotate across study days like a training split. Each language
/// alone, maths with a writing segment beside it, and reading alone. Maintenance courses aren't
/// in the split: their reviews ride in every session's warm-up.
public enum Split {
    static func groups(_ domains: [Domain]) -> [[Domain]] {
        var out: [[Domain]] = domains.filter(\.isLanguage).map { [$0] }
        if domains.contains(.maths) {
            out.append(domains.contains(.writing) ? [.maths, .writing] : [.maths])
        } else if domains.contains(.writing) {
            out.append([.writing])
        }
        if domains.contains(.reading) { out.append([.reading]) }
        return out
    }

    /// How much of the week each group gets. Languages most: they want near-daily exposure.
    static func weight(_ group: [Domain]) -> Double {
        switch group.first {
        case .japanese, .spanish: 2
        case .maths: 1.5
        case .writing: 1
        case .reading: 1.5
        default: 1
        }
    }

    /// The domains for each study day of the week starting `monday`. `priorities` are lagging
    /// domains that get more of the week (when auto-prioritise is on).
    public static func week(starting monday: Day, settings: MindSettings, priorities: Set<Domain> = []) -> [Day: [Domain]] {
        let days = settings.schedule.studyDays.map { monday.adding(days: $0.rawValue - 1) }
        let groups = groups(settings.focus)
        guard !days.isEmpty, !groups.isEmpty else { return [:] }
        let weights = groups.map { weight($0) + (settings.autoPrioritise && !priorities.isDisjoint(with: $0) ? 0.75 : 0) }
        var counts: [Int]
        if days.count < groups.count {
            // Fewer days than groups: rotate which groups get this week.
            let weekIndex = monday.ordinal / 7
            counts = Array(repeating: 0, count: groups.count)
            let order = groups.indices.sorted { weights[$0] > weights[$1] }
            for i in 0..<days.count { counts[order[(weekIndex * days.count + i) % groups.count]] += 1 }
        } else {
            let total = weights.reduce(0, +)
            let shares = weights.map { $0 / total * Double(days.count) }
            counts = shares.map { max(1, Int($0)) }
            while counts.reduce(0, +) > days.count,
                let i = counts.indices.filter({ counts[$0] > 1 }).max(by: { Double(counts[$0]) - shares[$0] < Double(counts[$1]) - shares[$1] })
            {
                counts[i] -= 1
            }
            while counts.reduce(0, +) < days.count,
                let i = counts.indices.max(by: { shares[$0] - Double(counts[$0]) < shares[$1] - Double(counts[$1]) })
            {
                counts[i] += 1
            }
        }
        // Spread them: each day takes the group with the most left that isn't yesterday's.
        var left = counts
        var out: [Day: [Domain]] = [:]
        var previous: Int?
        for day in days {
            let candidates = left.indices.filter { left[$0] > 0 }
            let pick =
                candidates.filter { $0 != previous }.max { (left[$0], weights[$0]) < (left[$1], weights[$1]) }
                ?? candidates.max { left[$0] < left[$1] }
            guard let pick else { break }
            out[day] = groups[pick]
            left[pick] -= 1
            previous = pick
        }
        return out
    }
}
