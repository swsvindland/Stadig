import Foundation

public enum BlockKind: String, Codable, Sendable {
    /// The first weeks: find working weights, calibrate trust, establish baseline scores.
    case assessment
    /// General strength and hypertrophy at normal volume, valid in any nutrition phase: used while
    /// the phase is still undecided.
    case neutral
    case standard
    /// Crunch mode's minimum effective dose.
    case minimumEffective

    public var label: String {
        switch self {
        case .assessment: "Assessment"
        case .neutral: "General block"
        case .standard: "Training block"
        case .minimumEffective: "Minimum effective dose"
        }
    }
}

public enum BlockWeek: Hashable, Sendable {
    case before
    /// Zero-based loading week.
    case loading(Int)
    case deload
    case after

    public var isDeload: Bool { self == .deload }
}

/// A mesocycle on the calendar: loading weeks, then a deload. Vacations and early deloads move
/// the deload and the end; the loading plan itself doesn't change.
public struct TrainingBlock: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var kind: BlockKind
    public var start: Day
    public var loadingWeeks: Int
    public var deloadWeeks: Int
    /// When the deload actually starts, if not after the planned loading weeks.
    public var deloadStart: Day?
    /// When the block actually ends, if not after the planned deload.
    public var endOverride: Day?
    public var deloadReason: String?

    public init(id: UUID = UUID(), kind: BlockKind, start: Day, loadingWeeks: Int, deloadWeeks: Int = 1, deloadStart: Day? = nil,
                endOverride: Day? = nil, deloadReason: String? = nil) {
        self.id = id
        self.kind = kind
        self.start = start
        self.loadingWeeks = max(1, loadingWeeks)
        self.deloadWeeks = max(0, deloadWeeks)
        self.deloadStart = deloadStart
        self.endOverride = endOverride
        self.deloadReason = deloadReason
    }

    public var plannedDeloadStart: Day { start.adding(weeks: loadingWeeks) }
    public var effectiveDeloadStart: Day { deloadStart ?? plannedDeloadStart }
    public var end: Day { endOverride ?? effectiveDeloadStart.adding(days: deloadWeeks * 7 - 1) }
    public var range: DayRange { DayRange(start, end) }

    public var deloadRange: DayRange? {
        let s = effectiveDeloadStart
        guard s <= end, deloadWeeks > 0 || deloadStart != nil else { return nil }
        return DayRange(s, end)
    }

    public func week(of day: Day) -> BlockWeek {
        if day < start { return .before }
        if day > end { return .after }
        if day >= effectiveDeloadStart { return .deload }
        return .loading(min(loadingWeeks - 1, start.days(until: day) / 7))
    }

    /// The day benchmark tests and check-ins land: the end of the deload, when fresh.
    public var checkInDay: Day? { deloadRange?.end }

    public var weeksTotal: Int { (start.days(until: end) + 1 + 6) / 7 }
}

public enum BlockScheduler {
    public static let defaultLoadingWeeks = 5
    public static let loadingRange = 3...8
    /// Vacations shorter than this don't reshape a block; their days are exempt anyway.
    public static let minimumReflowDays = 4

    /// Loading weeks: 5 by default, shorter in a cut, longer in a bulk and for beginners who
    /// recover quickly.
    public static func loadingWeeks(phase: PhaseEffects, experience: TrainingExperience) -> Int {
        var weeks = defaultLoadingWeeks + phase.blockLengthAdjustment
        if experience == .novice { weeks += 1 }
        return clamp(weeks, loadingRange.lowerBound, loadingRange.upperBound)
    }

    /// Fits a block around vacations. Near the planned deload, the vacation becomes the deload.
    /// Early in the block, the block is cut short, the vacation counts as the deload, and a fresh
    /// block starts afterwards. In the first few days, the block simply starts after it. One that
    /// starts during the deload keeps it and stretches it over the trip.
    public static func reflow(_ block: TrainingBlock, vacations: [DayRange]) -> TrainingBlock {
        var block = block
        for vacation in vacations.sorted(by: { $0.start < $1.start }) where vacation.count >= minimumReflowDays {
            guard vacation.overlaps(block.range) else { continue }
            let loadingDone = block.start.days(until: vacation.start)
            if loadingDone < 5 {
                let shift = block.start.days(until: vacation.end.adding(days: 1))
                block.start = vacation.end.adding(days: 1)
                if let d = block.deloadStart { block.deloadStart = d.adding(days: shift) }
                if let e = block.endOverride { block.endOverride = e.adding(days: shift) }
                continue
            }
            if vacation.start >= block.effectiveDeloadStart {
                // Already deloading when the trip starts: the deload days stay deload days (moving
                // the start would turn them back into the hardest loading week), and the deload runs
                // on through the trip.
                if vacation.end > block.end {
                    block.endOverride = vacation.end
                    block.deloadReason = "Your vacation starts during the deload, so the deload runs through the trip."
                }
                continue
            }
            block.deloadStart = vacation.start
            block.endOverride = vacation.end
            let nearDeload = vacation.start >= block.plannedDeloadStart.adding(days: -14)
            block.deloadReason = nearDeload
                ? "Your vacation lands near the planned deload, so it becomes the deload."
                : "Your vacation comes early in the block, so the block ends there and the trip counts as the deload. A fresh block starts after."
        }
        return block
    }

    /// Moves the deload to now when the Fatigue Budget says so, after at least two loading weeks.
    public static func deloadEarly(_ block: TrainingBlock, today: Day, fatigue: FatigueAssessment) -> TrainingBlock? {
        guard fatigue.action == .deloadEarly, case .loading(let week) = block.week(of: today), week >= 2 else { return nil }
        var block = block
        block.deloadStart = today
        block.endOverride = today.adding(days: 6)
        block.deloadReason = "Signs of accumulated fatigue (\(fatigue.signals.prefix(2).joined(separator: " ").lowercased())), so the deload comes early."
        return block
    }

    /// The system-wide calendar every app aligns to.
    public static func calendar(blocks: [TrainingBlock], today: Day, publishedBy: AppID = .liftTrack) -> SystemCalendar {
        let current = blocks.first { $0.range.contains(today) }
        return SystemCalendar(currentBlock: current?.range, deloads: blocks.compactMap(\.deloadRange).filter { $0.end >= today },
                              checkIns: blocks.compactMap(\.checkInDay).filter { $0 >= today }, publishedBy: publishedBy)
    }
}
