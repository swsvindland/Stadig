import ExerciseLibrary
import Foundation
import SystemCore

/// A block laid out for planning: each slot's sets week by week, and the block's days on a
/// calendar. What the Program screen shows on the iPad and the Mac.
public enum ProgramLayout {
    /// One week's working sets for a slot.
    public struct WeekSets: Hashable, Sendable {
        public var week: BlockWeek
        public var sets: Int

        public var isDeload: Bool { week.isDeload }
    }

    /// A slot's working sets in each week of the block: the loading weeks as planned, then the
    /// deload's. Empty for work that isn't counted in sets (drills, conditioning, the sauna).
    public static func setsByWeek(_ slot: SlotPlan, block: TrainingBlock) -> [WeekSets] {
        guard slot.role == .main || slot.role == .accessory else { return [] }
        let loading = (0..<block.loadingWeeks).map { WeekSets(week: .loading($0), sets: slot.sets(week: $0)) }
        guard block.deloadWeeks > 0 || block.deloadStart != nil else { return loading }
        return loading + [WeekSets(week: .deload, sets: deloadSets(lastLoadingWeek: slot.sets(week: block.loadingWeeks - 1)))]
    }

    /// The deload's working sets: half the last loading week's, rounded up, at least one, as
    /// `Progression.prescribe` gives a deload.
    public static func deloadSets(lastLoadingWeek sets: Int) -> Int { max(1, Int((Double(sets) / 2).rounded(.up))) }

    /// "3·3·4·4 · 2": the loading weeks, then the deload after a wider gap.
    public static func summary(_ weeks: [WeekSets]) -> String {
        let loading = weeks.filter { !$0.isDeload }.map { String($0.sets) }.joined(separator: "·")
        guard let deload = weeks.first(where: \.isDeload) else { return loading }
        return "\(loading) · \(deload.sets)"
    }

    // MARK: Calendar

    /// One day of the block on the calendar.
    public struct CalendarDay: Hashable, Sendable, Identifiable {
        public var day: Day
        public var week: BlockWeek
        /// One of the person's training days, inside the block.
        public var training: Bool
        /// A Stadig Lift session was done that day.
        public var trained: Bool
        public var vacation: Bool
        /// The deload's check-in: tests and rep-outs land then.
        public var checkIn: Bool
        public var isToday: Bool

        public var id: Day { day }
        public var inBlock: Bool { week != .before && week != .after }
    }

    /// A week of the block, counted from the block's first day (as the week strip counts them).
    public struct CalendarWeek: Hashable, Sendable, Identifiable {
        public var start: Day
        public var week: BlockWeek
        public var days: [CalendarDay]

        public var id: Day { start }
    }

    /// The block's weeks, each its seven days from the block's start weekday: which are training
    /// days, which were trained, the vacations, the deload, the check-in and today. A block a
    /// vacation cut short ends early: the last week's days past the end are outside the block.
    public static func calendar(
        block: TrainingBlock, trainingDays: Set<Weekday>, trained: Set<Day>, vacations: [DayRange], today: Day
    ) -> [CalendarWeek] {
        let checkIn = block.checkInDay
        return (0..<max(1, block.weeksTotal)).map { index in
            let start = block.start.adding(weeks: index)
            let days = (0..<7).map { offset -> CalendarDay in
                let day = start.adding(days: offset)
                let week = block.week(of: day)
                let inBlock = week != .before && week != .after
                let away = vacations.contains { $0.contains(day) }
                return CalendarDay(
                    day: day, week: week, training: inBlock && !away && trainingDays.contains(day.weekday), trained: trained.contains(day),
                    vacation: away, checkIn: day == checkIn, isToday: day == today)
            }
            return CalendarWeek(start: start, week: block.week(of: start), days: days)
        }
    }
}
