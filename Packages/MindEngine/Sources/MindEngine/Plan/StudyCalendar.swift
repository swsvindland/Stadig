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

/// The study calendar. With Stadig Lift installed, review weeks are the system deloads it
/// publishes; on its own, Stadig Mind runs five weeks then a review week.
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

    /// The last day from `day` on that the phase reads as it does on `day` (its label: this week of a
    /// block, the review week, a pause), looking up to `horizon` days ahead; nil when it still does
    /// at the horizon, as a pause with no end set does. A widget drawn days after the app last ran
    /// keeps the phase it was given until then.
    public static func lastDay(
        ofPhaseOn day: Day, start: Day, calendar: SystemCalendar?, lifeModes: [LifeModePeriod], horizon: Int = 60
    ) -> Day? {
        let label = phase(on: day, start: start, calendar: calendar, lifeModes: lifeModes).label
        for offset in 1...max(1, horizon) {
            let next = day.adding(days: offset)
            if phase(on: next, start: start, calendar: calendar, lifeModes: lifeModes).label != label { return next.adding(days: -1) }
        }
        return nil
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

    /// Vacation, illness and crunch mode pause Stadig Mind (a five-minute review is offered in
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
