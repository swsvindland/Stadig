import Foundation
import SystemCore

extension ProgramLayout {
    /// One slot in one week of the block, as the program desk shows it: what was done that week, what
    /// the next session asks for, or what the block still has in store.
    public struct LedgerCell: Hashable, Sendable {
        public enum State: Hashable, Sendable {
            /// Done: the session's working sets, as logged.
            case done
            /// The next session's targets, as it's planned now.
            case next
            /// Still to come: the block's sets and rep range. The load is worked out on the day, from
            /// how the sets before it went, so there's none to show yet.
            case planned
            /// The week has gone and the day wasn't done, or the session left this slot out.
            case missed
        }

        public var week: BlockWeek
        public var state: State
        /// Working sets done, or planned.
        public var sets: Int
        /// The heaviest working set's reps when done ("7"), the next session's target ("6"), or the
        /// block's range ("5–8").
        public var reps: String
        /// The heaviest working set's load, or the next session's first work set's. Nil when the
        /// load is picked on the day (a finding-weight set) or still to be worked out.
        public var loadKg: Double?
        /// Timed work: the heaviest set's seconds.
        public var seconds: Int?
        /// How each working set felt, in order: done cells only.
        public var ratings: [SetRating]
        /// The load against the latest earlier week that has one.
        public var changeKg: Double?
    }

    /// A day of the block in one week: done on a day, the next session, or to come.
    public struct LedgerDayWeek: Hashable, Sendable {
        public var week: BlockWeek
        /// When it was done that week.
        public var done: Day?
        public var isNext: Bool
        /// Gone without being done.
        public var missed: Bool
    }

    /// The block's weeks, as columns: the loading weeks, then the deload when there is one.
    public static func weeks(of block: TrainingBlock) -> [BlockWeek] {
        let loading = (0..<max(1, block.loadingWeeks)).map(BlockWeek.loading)
        return block.deloadWeeks > 0 || block.deloadStart != nil ? loading + [.deload] : loading
    }

    /// Each week's working sets across the block's lifts, against the heaviest week's: how hard each
    /// week is, 0 to 1, for the rulers over the columns.
    public static func weekLoads(_ mesocycle: Mesocycle) -> [Double] {
        let weeks = weeks(of: mesocycle.block)
        let slots = mesocycle.days.flatMap(\.strengthSlots)
        let totals = weeks.map { week in
            Double(slots.map { setsByWeek($0, block: mesocycle.block).first { $0.week == week }?.sets ?? 0 }.reduce(0, +))
        }
        let peak = totals.max() ?? 0
        return totals.map { peak > 0 ? $0 / peak : 0 }
    }

    /// A day across the block's weeks: when it was done in each, and which week has it next.
    public static func ledger(day: PlannedDay, of mesocycle: Mesocycle, records: [SessionRecord], next: SessionPlan?, today: Day)
        -> [LedgerDayWeek]
    {
        let block = mesocycle.block
        let current = block.week(of: today)
        let done = sessions(of: day, in: mesocycle, records: records)
        let nextWeek = nextWeek(of: day, in: mesocycle, next: next, done: done)
        return weeks(of: block).map { week in
            let record = done[week]
            return LedgerDayWeek(
                week: week, done: record?.day, isNext: week == nextWeek,
                missed: record == nil && week != nextWeek && isBefore(week, current))
        }
    }

    /// A slot across the block's weeks: what was done in each week gone, the next session's targets,
    /// and the sets and reps still to come.
    public static func ledger(
        slot: SlotPlan, day: PlannedDay, of mesocycle: Mesocycle, records: [SessionRecord], next: SessionPlan?, today: Day
    ) -> [LedgerCell] {
        let block = mesocycle.block
        let current = block.week(of: today)
        let done = sessions(of: day, in: mesocycle, records: records)
        let nextWeek = nextWeek(of: day, in: mesocycle, next: next, done: done)
        let planned = setsByWeek(slot, block: block)
        var cells: [LedgerCell] = []
        for week in weeks(of: block) {
            let sets = planned.first { $0.week == week }?.sets ?? 0
            var cell: LedgerCell
            if let record = done[week] {
                cell = doneCell(slot, record: record, week: week)
            } else if week == nextWeek, let next, let item = next.items.first(where: { $0.slotID == slot.id }) {
                let work = item.workSets
                cell = LedgerCell(
                    week: week, state: .next, sets: work.count, reps: work.first.map { "\($0.targetReps)" } ?? slot.repRange.label,
                    loadKg: work.first?.loadKg, seconds: work.first?.seconds, ratings: [], changeKg: nil)
            } else {
                cell = LedgerCell(
                    week: week, state: isBefore(week, current) ? .missed : .planned, sets: sets, reps: slot.repRange.label, loadKg: nil,
                    seconds: slot.seconds, ratings: [], changeKg: nil)
            }
            if cell.state == .done || cell.state == .next, let load = cell.loadKg,
                let earlier = cells.last(where: { $0.loadKg != nil && ($0.state == .done || $0.state == .next) })?.loadKg
            {
                cell.changeKg = load - earlier
            }
            cells.append(cell)
        }
        return cells
    }

    /// The working sets one session logged for a slot: by the slot when the log carries it, else the
    /// slot's exercise (a session saved before logs kept their slot). A slot the session swapped
    /// keeps the sets done in its place.
    private static func doneCell(_ slot: SlotPlan, record: SessionRecord, week: BlockWeek) -> LedgerCell {
        let log = record.exercises.first { $0.slotID == slot.id } ?? record.exercises.first { $0.slotID == nil && $0.exerciseID == slot.exerciseID }
        let work = log?.sets.filter(\.kind.countsAsWork) ?? []
        guard let top = work.max(by: { ($0.loadKg, $0.reps) < ($1.loadKg, $1.reps) }) else {
            return LedgerCell(
                week: week, state: .missed, sets: 0, reps: slot.repRange.label, loadKg: nil, seconds: nil, ratings: [], changeKg: nil)
        }
        return LedgerCell(
            week: week, state: .done, sets: work.count, reps: "\(top.reps)", loadKg: top.loadKg, seconds: top.seconds,
            ratings: work.compactMap(\.rating), changeKg: nil)
    }

    /// The latest session of a day in each week of the block.
    private static func sessions(of day: PlannedDay, in mesocycle: Mesocycle, records: [SessionRecord]) -> [BlockWeek: SessionRecord] {
        var byWeek: [BlockWeek: SessionRecord] = [:]
        for record in records where record.mesocycleID == mesocycle.id && record.dayID == day.id {
            let week = mesocycle.block.week(of: record.day)
            if let kept = byWeek[week], kept.start > record.start { continue }
            byWeek[week] = record
        }
        return byWeek
    }

    /// The week the next session falls in, when it's this day and the day isn't done that week yet.
    private static func nextWeek(of day: PlannedDay, in mesocycle: Mesocycle, next: SessionPlan?, done: [BlockWeek: SessionRecord])
        -> BlockWeek?
    {
        guard let next, next.mesocycleID == mesocycle.id, next.dayID == day.id else { return nil }
        let week = mesocycle.block.week(of: next.day)
        return done[week] == nil ? week : nil
    }

    private static func isBefore(_ week: BlockWeek, _ current: BlockWeek) -> Bool { order(week) < order(current) }

    private static func order(_ week: BlockWeek) -> Int {
        switch week {
        case .before: -1
        case .loading(let index): index
        case .deload: 1_000
        case .after: 2_000
        }
    }
}
