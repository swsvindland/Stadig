import Foundation
import SystemCore

// What the iPhone's Plan and session summary show beyond the plan itself: this week as a list of
// sessions, and a finished session's numbers against its plan and the last time.

/// One of this week's sessions on Plan: done, today's, or still to come on a training day.
public struct WeekSession: Hashable, Sendable, Identifiable {
    public enum State: Hashable, Sendable {
        case done
        case today
        case planned
    }

    public var day: Day
    public var title: String
    /// What it took, once done; the plan's minutes before.
    public var minutes: Int
    public var state: State
    /// The program's day: what a row opens.
    public var dayID: UUID?
    /// The record, once done.
    public var sessionID: UUID?

    public var id: String { sessionID?.uuidString ?? "\(day.description)-\(title)" }
}

public enum ThisWeek {
    /// This week, Monday to Sunday: every session done in it (extras too), in order, then the ones the
    /// plan still expects, on the training days left, in the program's rotation from `next`. Today
    /// counts as left while today's session is still to do.
    public static func sessions(next: NextSession?, records: [SessionRecord], trainingDays: [Weekday], today: Day) -> [WeekSession] {
        let monday = today.startOfWeek
        let sunday = monday.adding(days: 6)
        let done = records.filter { $0.day >= monday && $0.day <= sunday }.sorted { $0.start < $1.start }
        var rows = done.map { record in
            WeekSession(
                day: record.day, title: record.title, minutes: record.minutes, state: .done, dayID: record.dayID, sessionID: record.id)
        }
        guard let next, !next.mesocycle.days.isEmpty else { return rows }
        let left = max(0, next.plannedThisWeek - next.doneThisWeek)
        let trained = Set(done.map(\.day))
        let from = next.scheduledToday ? today : today.adding(days: 1)
        let days = (0..<7).map { from.adding(days: $0) }
            .filter { $0 <= sunday && trainingDays.contains($0.weekday) && !trained.contains($0) }
            .prefix(left)
        for (offset, day) in days.enumerated() {
            let planned = next.mesocycle.days[(next.dayIndex + offset) % next.mesocycle.days.count]
            rows.append(
                WeekSession(
                    day: day, title: planned.name, minutes: planned.minutes, state: day == today ? .today : .planned, dayID: planned.id,
                    sessionID: nil))
        }
        return rows
    }
}

/// A finished session in numbers: its minutes against the plan's, its work sets against the plan's,
/// and what it lifted against the last time the same day of the program was done.
public struct SessionTally: Hashable, Sendable {
    public var minutes: Int
    /// The plan's minutes less what it took: positive when it was quicker.
    public var underPlan: Int?
    public var sets: Int
    public var plannedSets: Int?
    /// Every work set's load times its reps.
    public var liftedKg: Double
    /// Against the last time: 0.04 for 4% more.
    public var liftedChange: Double?

    public init(_ record: SessionRecord, plannedMinutes: Int?, plannedSets: Int?, earlier: [SessionRecord]) {
        minutes = record.minutes
        underPlan = plannedMinutes.map { $0 - record.minutes }
        sets = record.workSets.count
        self.plannedSets = plannedSets
        liftedKg = record.liftedKg
        // The same day of the program, or a session of the same name when it wasn't one.
        let last =
            earlier
            .filter { $0.id != record.id && $0.start < record.start && $0.liftedKg > 0 }
            .filter { record.dayID != nil ? $0.dayID == record.dayID : $0.title == record.title }
            .max { $0.start < $1.start }
        if let last, liftedKg > 0 { liftedChange = liftedKg / last.liftedKg - 1 } else { liftedChange = nil }
    }
}

extension SessionRecord {
    /// Every work set's load times its reps, in kilograms.
    public var liftedKg: Double { workSets.reduce(0) { $0 + $1.loadKg * Double($1.reps) } }
}
