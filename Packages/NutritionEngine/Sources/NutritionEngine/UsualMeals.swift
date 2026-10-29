import Foundation
import SystemCore

/// A time of day this person usually eats, and what they last ate then: what a day that wasn't
/// logged as it happened is caught up from ("12:30 PM: chicken and rice, as on Monday").
public struct UsualMeal: Hashable, Sendable, Identifiable {
    /// The usual time, on the day asked about.
    public var time: Date
    /// How many of the days read had a meal within ``UsualMeals/radius`` of it.
    public var days: Int
    /// The most recent meal eaten around this time on another day: what to log again.
    public var latest: Moment
    /// Whether the day asked about already has a meal around this time.
    public var logged: Bool

    public var id: Date { time }
}

public enum UsualMeals {
    /// How far from a usual time a meal still counts as eaten then: lunch at 11:45 one day and
    /// 1:15 the next is one lunch, while a snack two hours after it is a time of its own.
    public static let radius: TimeInterval = 60 * 60
    /// Days read, back from today.
    public static let lookback = 28
    /// The share of the days read with a meal logged that a time needs a meal around it on to be
    /// usual (and two days at least): a snack eaten twice a week is, one eaten twice a month isn't.
    public static let share = 0.25

    /// The times of day this person usually eats, earliest first, placed on `day`, each with what
    /// was last eaten then and whether `day` has a meal then already. Read from meals (moments of
    /// ``MealTiming/mealKcal`` or more, so a black coffee isn't one) over the ``lookback`` days to
    /// `today`, leaving out `day` itself, so catching up yesterday learns from today too.
    ///
    /// Picked greedily, the time with meals on the most days first: each day's meal nearest it is
    /// taken, and the usual time is the middle of theirs, rounded to 5 minutes. The rest of those
    /// days' meals are left for the next time, so lunch at 12:30 and a snack at 3:30 stay apart.
    public static func on(_ day: Day, entries: [FoodEntry], today: Day, calendar: Calendar = .current) -> [UsualMeal] {
        let from = today.adding(days: -lookback)
        let read = entries.filter { $0.day >= from && $0.day <= today && $0.day != day }
        var meals: [(day: Day, minute: Double, moment: Moment)] = []
        for (mealDay, dayEntries) in Dictionary(grouping: read, by: \.day) {
            for moment in MealTiming.meals(dayEntries) { meals.append((mealDay, minuteOfDay(moment.start, calendar), moment)) }
        }
        // Dictionary order isn't stable: ties between candidates would go a different way each run.
        meals.sort { $0.moment.start < $1.moment.start }
        let needed = max(2, Int((Double(Set(meals.map(\.day)).count) * share).rounded(.up)))
        let times = meals.map { (day: $0.day, minute: $0.minute) }

        var left = Set(meals.indices)
        var found: [(minute: Int, members: [Int])] = []
        while true {
            var best: (members: [Int], spread: Double, minute: Double)?
            for candidate in left.sorted() {
                let members = nearestEachDay(to: meals[candidate].minute, among: left, times)
                let spread = members.map { abs(offset(meals[$0].minute, from: meals[candidate].minute)) }.reduce(0, +)
                if let best, members.count < best.members.count || (members.count == best.members.count && spread >= best.spread) { continue }
                best = (members, spread, meals[candidate].minute)
            }
            guard let best, best.members.count >= needed else { break }
            left.subtract(best.members)
            // The middle of the meals taken, measured around the clock from the candidate so a usual
            // time near midnight isn't averaged to noon.
            let offsets = best.members.map { offset(meals[$0].minute, from: best.minute) }.sorted()
            let middle =
                offsets.count.isMultiple(of: 2) ? (offsets[offsets.count / 2 - 1] + offsets[offsets.count / 2]) / 2 : offsets[offsets.count / 2]
            let minute = (Int(((best.minute + middle) / 5).rounded()) * 5 + 1440) % 1440
            if !found.contains(where: { $0.minute == minute }) { found.append((minute, best.members)) }
        }

        let todaysMeals = MealTiming.meals(entries.filter { $0.day == day }).map { minuteOfDay($0.start, calendar) }
        return found.sorted { $0.minute < $1.minute }.compactMap { slot in
            guard let latest = slot.members.map({ meals[$0].moment }).max(by: { $0.start < $1.start }) else { return nil }
            let logged = todaysMeals.contains { abs(offset($0, from: Double(slot.minute))) * 60 < radius }
            return UsualMeal(time: day.at(minutes: slot.minute, calendar: calendar), days: slot.members.count, latest: latest, logged: logged)
        }
    }

    /// Of the meals in `pool`, each day's one nearest `minute` and within ``radius`` of it (the
    /// earlier of two as near, whatever order the set gives them in).
    static func nearestEachDay(to minute: Double, among pool: Set<Int>, _ meals: [(day: Day, minute: Double)]) -> [Int] {
        var nearest: [Day: (index: Int, distance: Double)] = [:]
        for i in pool {
            let distance = abs(offset(meals[i].minute, from: minute))
            guard distance * 60 < radius else { continue }
            if let current = nearest[meals[i].day], current.distance < distance || (current.distance == distance && current.index < i) {
                continue
            }
            nearest[meals[i].day] = (i, distance)
        }
        return nearest.values.map(\.index).sorted()
    }

    /// Minutes from `origin` to `minute` the short way around the clock: -90 is an hour and a half before.
    static func offset(_ minute: Double, from origin: Double) -> Double {
        var d = (minute - origin).truncatingRemainder(dividingBy: 1440)
        if d > 720 { d -= 1440 }
        if d <= -720 { d += 1440 }
        return d
    }

    static func minuteOfDay(_ date: Date, _ calendar: Calendar) -> Double { LogAgain.hourOfDay(date, calendar) * 60 }
}
