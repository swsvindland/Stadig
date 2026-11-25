import Foundation
import SystemCore

/// What Today shows over the day about the week's check-in: the one moment a week the plan and its
/// targets are looked at, so it's in sight rather than folded under the rest of the day.
public enum WeekCheckIn: Hashable, Sendable {
    /// A change to the plan the check-in found (`MacroAnalysis.planCheck`), until it's used or kept.
    case planCheck(PhasePlan)
    /// The check-in itself, and the one before it to say what moved: from its day for two days
    /// more, until it's put away.
    case targets(CheckIn, previous: CheckIn?)

    /// Which it is, steady across recomputes (a plan check's change is worked out afresh each time,
    /// stamped with the moment), for animating it in and out.
    public var id: String {
        switch self {
        case .planCheck(let change): "plan-check-\(change.headline)"
        case .targets(let checkIn, _): "check-in-\(checkIn.day.iso)"
        }
    }
}

extension CheckIns {
    /// How many days after its own a check-in stays on Today, unless it's put away first.
    public static let shownDays = 2

    /// Whether `checkIn` is a week's own, made when one was due, rather than the person's between
    /// two (a plan started, their own targets set or given up), which they've just seen for
    /// themselves.
    public static func isWeekly(_ checkIn: CheckIn, after previous: CheckIn?) -> Bool {
        guard let previous else { return false }
        return checkIn.day >= next(after: previous.day)
    }

    /// What Today shows of the check-in in force: a plan check first, else a weekly check-in for a
    /// couple of days after it, unless the person put it away (`MacroSettings.checkInPutAway`).
    /// `checkIns` are oldest first, as `MacroState` has them, with the one due today among them.
    public static func shown(_ checkIns: [CheckIn], planCheck: PhasePlan?, putAway: Day?, today: Day) -> WeekCheckIn? {
        if let planCheck { return .planCheck(planCheck) }
        guard let current = checkIns.last(where: { $0.day <= today }), current.day != putAway,
            current.day.days(until: today) <= shownDays
        else { return nil }
        let previous = checkIns.last { $0.day < current.day }
        guard isWeekly(current, after: previous) else { return nil }
        return .targets(current, previous: previous)
    }
}
