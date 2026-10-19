import Foundation
import SystemCore

/// How a day's log stands, in the history.
public enum HistoryStatus: String, Sendable, CaseIterable, Comparable {
    /// Teaches the estimate: marked complete, or finished with enough logged.
    case complete
    /// Marked fasted, with nothing eaten: it teaches the estimate too.
    case fasting
    /// Something logged, but not all of it (or marked partly logged): left out of the estimate.
    case partial
    /// Nothing logged and nothing said: not a miss, just not known.
    case unknown
    /// Today, still being logged.
    case inProgress

    public var label: String {
        switch self {
        case .complete: "Complete"
        case .fasting: "Fasted"
        case .partial: "Partial"
        case .unknown: "Unknown"
        case .inProgress: "Today"
        }
    }

    public static func < (a: HistoryStatus, b: HistoryStatus) -> Bool {
        let order = allCases
        return order.firstIndex(of: a) ?? 0 < order.firstIndex(of: b) ?? 0
    }
}

/// One day of the history: what was eaten against that day's targets, how complete the log is,
/// and the weight.
public struct HistoryDay: Identifiable, Hashable, Sendable {
    public var day: Day
    /// Food and supplements' calories, as Today counts them; nil when nothing was logged.
    public var intake: Nutrients?
    public var entries: Int
    /// The targets as they stood that day (its check-in, phase and life modes).
    public var targets: DailyTargets
    public var status: HistoryStatus
    /// The day's weigh-in that counts (the last one, when there were two), kg.
    public var weighIn: Double?
    /// The weight trend that day, kg.
    public var trend: Double?

    public var id: Day { day }

    public var kcal: Double? { intake?.kcal }

    /// Calories over (positive) or under (negative) the day's target.
    public var kcalOverTarget: Double? {
        guard let kcal = intake?.kcal, let target = targets.kcal else { return nil }
        return kcal - target
    }

    /// Whether a complete day met its targets (protein at least 90%, calories within 10%): nil for
    /// days that don't teach the estimate, or with nothing to judge, as Discipline judges them.
    public var hit: Bool? {
        guard status == .complete || status == .fasting else { return nil }
        let result = targets.hits(intake ?? .zero)
        switch (result.protein, result.calories) {
        case (nil, nil): return nil
        case (let p?, nil): return p
        case (nil, let c?): return c
        case (let p?, let c?): return p && c
        }
    }
}

public enum DayHistory {
    /// Every day from the first thing logged or weighed (or the assessment's start) to today, newest
    /// first, judged as the analysis judges them: a day it uses for the estimate is complete (or
    /// fasted); one with food it doesn't use is partial; one with nothing is unknown, never a miss.
    public static func rows(_ state: MacroState, _ analysis: MacroAnalysis) -> [HistoryDay] {
        let today = state.today
        let entriesByDay = Dictionary(grouping: state.entries, by: \.day)
        let counted = Dictionary(grouping: state.weighIns.filter(Weight.counts), by: \.day)
        let trend = Dictionary(analysis.trend.points.map { ($0.day, $0.trend) }, uniquingKeysWith: { _, last in last })
        let states = Dictionary(state.dayStatus.map { ($0.day, $0.state) }, uniquingKeysWith: { first, _ in first })
        let starts = [
            state.entries.map(\.day).min(), state.weighIns.map(\.day).min(), state.settings.assessmentStart,
            state.dayStatus.map(\.day).min(),
        ]
        guard let first = starts.compactMap({ $0 }).min(), first <= today else { return [] }
        return DayRange(first, today).days.reversed().map { day in
            let intake = analysis.intakeByDay[day]
            let status: HistoryStatus
            if let kcal = analysis.usable[day] {
                status = kcal == 0 ? .fasting : .complete
            } else if day == today {
                status = .inProgress
            } else if intake != nil || states[day] == .partial || states[day] == .inProgress {
                status = .partial
            } else {
                status = .unknown
            }
            return HistoryDay(
                day: day, intake: intake, entries: entriesByDay[day]?.count ?? 0,
                targets: day == today ? analysis.targets : analysis.dayTargets[day] ?? MacroAnalyst.targets(on: day, state, analysis),
                status: status, weighIn: counted[day]?.max { $0.date < $1.date }?.kg, trend: trend[day])
        }
    }
}

extension MacroAnalyst {
    /// A past day's targets as they stood that day: its life modes, the check-in then in force, the
    /// plan's phase, a deload, and only protein before the plan began. The same as the analysis
    /// gives the days it scores (`dayTargets`), for any day.
    public static func targets(on day: Day, _ state: MacroState, _ a: MacroAnalysis) -> DailyTargets {
        let planStart = (state.plan?.created).map { Day($0) }
        let assessing = state.plan == nil || day < planStart ?? day
        return Targets.today(
            day: day, assessing: assessing, plan: state.plan, override: state.settings.phaseOverride, maintenance: a.maintenance,
            checkIn: state.checkIns.last { $0.day <= day }, weightKg: a.plannerInput.weightKg, heightCm: state.profile.heightCm,
            waistToHeight: a.plannerInput.waistToHeight, life: LifeModes.effects(on: day, periods: state.lifeModes),
            deload: state.calendar?.isDeload(day) ?? false)
    }
}

/// The history table sorted by one of its columns. Days without the value (no weigh-in, nothing
/// logged) go last whichever way the column is sorted; ties go newest first.
public struct HistoryOrder: SortComparator, Hashable, Sendable {
    public enum Column: String, Hashable, Sendable {
        case day, kcal, overTarget, protein, carbs, fat, fiber, status, weighIn, trend
    }

    public var column: Column
    public var order: SortOrder

    public init(_ column: Column, order: SortOrder = .forward) {
        self.column = column
        self.order = order
    }

    public func compare(_ a: HistoryDay, _ b: HistoryDay) -> ComparisonResult {
        switch column {
        case .day: return directed(Self.compare(a.day, b.day))
        case .kcal: return ordered(a.intake?.kcal, b.intake?.kcal, a, b)
        case .overTarget: return ordered(a.kcalOverTarget, b.kcalOverTarget, a, b)
        case .protein: return ordered(a.intake?.protein, b.intake?.protein, a, b)
        case .carbs: return ordered(a.intake?.carbs, b.intake?.carbs, a, b)
        case .fat: return ordered(a.intake?.fat, b.intake?.fat, a, b)
        case .fiber: return ordered(a.intake?.fiber, b.intake?.fiber, a, b)
        case .status: return ordered(a.status, b.status, a, b)
        case .weighIn: return ordered(a.weighIn, b.weighIn, a, b)
        case .trend: return ordered(a.trend, b.trend, a, b)
        }
    }

    private func directed(_ result: ComparisonResult) -> ComparisonResult {
        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    /// Present values in the column's order, missing ones after them either way, then newest first.
    private func ordered<T: Comparable>(_ x: T?, _ y: T?, _ a: HistoryDay, _ b: HistoryDay) -> ComparisonResult {
        switch (x, y) {
        case (let x?, let y?):
            let result = Self.compare(x, y)
            return result == .orderedSame ? Self.compare(b.day, a.day) : directed(result)
        case (.some, nil): return .orderedAscending
        case (nil, .some): return .orderedDescending
        case (nil, nil): return Self.compare(b.day, a.day)
        }
    }

    static func compare<T: Comparable>(_ x: T, _ y: T) -> ComparisonResult { x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame }
}
