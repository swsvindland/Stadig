import Foundation
import SystemCore

/// The arithmetic behind the Health reads, kept free of HealthKit so it can be tested without data.
enum HealthMath {
    /// The day a stretch of sleep counts towards: a night ending between noon the previous day and
    /// noon on a day belongs to that day.
    static func night(endingAt end: Date, calendar: Calendar = .current) -> Day {
        let day = Day(end, calendar: calendar)
        return calendar.component(.hour, from: end) >= 12 ? day.adding(days: 1) : day
    }

    /// Hours asleep per night. Overlapping intervals (several sources recording the same night) count once.
    static func sleepHours(_ intervals: [DateInterval], calendar: Calendar = .current) -> [Day: Double] {
        Dictionary(grouping: intervals) { night(endingAt: $0.end, calendar: calendar) }
            .mapValues { mergedDuration($0) / 3600 }
    }

    /// Total time covered by the intervals, counting overlaps once.
    static func mergedDuration(_ intervals: [DateInterval]) -> TimeInterval {
        var total: TimeInterval = 0
        var current: DateInterval?
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let run = current, interval.start <= run.end {
                current = DateInterval(start: run.start, end: max(run.end, interval.end))
            } else {
                total += current?.duration ?? 0
                current = interval
            }
        }
        return total + (current?.duration ?? 0)
    }

    /// Age-predicted maximum heart rate (Tanaka: 208 − 0.7 × age).
    static func maxHeartRate(age: Int) -> Double { 208 - 0.7 * Double(age) }

    /// RPE 1–10 from a session's average heart rate as a share of max: about 2 at 50%, two points per
    /// further 10%, 10 from 90% up.
    static func intensity(averageHeartRate: Double, maxHeartRate: Double) -> Int? {
        guard averageHeartRate > 0, maxHeartRate > 0 else { return nil }
        let share = averageHeartRate / maxHeartRate
        return clamp(Int((2 + (share - 0.5) * 20).rounded()), 1, 10)
    }

    /// Whole years between a date of birth and `date`; nil when the birth date is incomplete or later.
    /// HealthKit gives the birth date in Gregorian components whatever the person's calendar, so
    /// they're read in a Gregorian calendar (in `calendar`'s time zone): read in the Buddhist calendar,
    /// 1990 would be 1447 CE and the age 579.
    static func age(birth: DateComponents, on date: Date, calendar: Calendar = .current) -> Int? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        guard birth.year != nil, let born = gregorian.date(from: birth),
            let years = gregorian.dateComponents([.year], from: born, to: date).year, years >= 0
        else { return nil }
        return years
    }

    /// One entry per day from `start` through `end`; empty when no day in the range has any data.
    static func recoveryDays(
        from start: Day, through end: Day, sleep: [Day: Double], hrv: [Day: Double],
        restingHeartRate: [Day: Double]
    ) -> [RecoveryDay] {
        guard start <= end else { return [] }
        let days = DayRange(start, end).days.map {
            RecoveryDay(day: $0, sleepHours: sleep[$0], hrv: hrv[$0], restingHeartRate: restingHeartRate[$0])
        }
        return days.contains { $0 != RecoveryDay(day: $0.day) } ? days : []
    }
}
