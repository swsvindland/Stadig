import Foundation
import SystemCore

/// How the weight trend sits against the phase in force: the Plan tab's "On pace." and Progress's
/// sentence under the weight. A phase asks for a rate (a cut's −0.5% a week); the trend says what's
/// happening. The weekly check-in already moves the targets toward the rate, so this only says where
/// things stand, in words. With the person's own targets on, the trend is judged against what their
/// calories aim for from the maintenance estimate (`OwnTargets.aim`), not the plan's phase they've
/// set aside.
public enum PhasePace {
    public enum Verdict: String, Sendable, Equatable {
        /// Within a third or so of the phase's rate (or holding, at maintenance).
        case onPace
        /// Losing or gaining faster than the phase asks.
        case faster
        /// Moving the right way, but slower than the phase asks.
        case slower
        /// Gaining in a cut, losing in a bulk, or drifting at maintenance.
        case offCourse

        /// The words after the trend: "On pace."
        public var label: String {
            switch self {
            case .onPace: "On pace."
            case .faster: "Faster than planned."
            case .slower: "Slower than planned."
            case .offCourse: "Off course."
            }
        }

        /// The words after the trend under the person's own targets, which aim where their calories do.
        public var ownLabel: String {
            switch self {
            case .onPace: "On pace for your targets."
            case .faster: "Faster than your targets aim for."
            case .slower: "Slower than your targets aim for."
            case .offCourse: "The other way from your targets."
            }
        }
    }

    /// The share of the planned rate that still counts as on pace, either side.
    static let band = (low: 0.7, high: 1.4)
    /// At maintenance, the weekly drift, as a share of body weight, that still counts as holding.
    static let holding = 0.0025

    /// The verdict for a weekly change in the trend (kg a week) against the phase's rate, at the
    /// trend's weight. Nil without a phase or a trend.
    public static func verdict(weeklyChange: Double?, phase: PlannedPhase?, weightKg: Double) -> Verdict? {
        guard let phase else { return nil }
        return verdict(weeklyChange: weeklyChange, aim: phase.ratePerWeek * weightKg, weightKg: weightKg)
    }

    /// The verdict for a weekly change in the trend against an aim, both kg a week: 0 aims to hold.
    public static func verdict(weeklyChange: Double?, aim planned: Double, weightKg: Double) -> Verdict? {
        guard let change = weeklyChange, weightKg > 0 else { return nil }
        guard planned != 0 else { return abs(change) <= holding * weightKg ? .onPace : .offCourse }
        let ratio = change / planned
        if ratio <= 0 { return .offCourse }
        if ratio < band.low { return .slower }
        if ratio > band.high { return .faster }
        return .onPace
    }

    /// Where the phase's own rate takes the trend by the phase's last day: the weight it's aiming
    /// at, not a line drawn through a fast week. Nil once the phase has ended, or at maintenance.
    public static func aim(trendKg: Double, phase: PlannedPhase, today: Day) -> (kg: Double, day: Day)? {
        guard phase.ratePerWeek != 0, today <= phase.end else { return nil }
        let weeksLeft = Double(today.days(until: phase.end)) / 7
        return (trendKg * (1 + phase.ratePerWeek * weeksLeft), phase.end)
    }

    /// The next weekly check-in: a week after the last, or today when one's due.
    public static func nextCheckIn(last: CheckIn?, today: Day) -> Day {
        guard let last, !CheckIns.isDue(last: last, today: today) else { return today }
        return last.day.adding(days: 7)
    }
}
