import Foundation
import SystemCore

// When meals happen: the gaps between them, the overnight fast, the eating window and the last meal
// before bed, read from the log with nothing extra to tap. Only days whose log can be trusted are
// read (complete, fasted, or today so far): an unlogged snack would look like a long gap.
//
// What's behind the bands. Grazing is the end with results against it: the same extra calories
// eaten as snacks between meals raised liver fat in a trial where eaten with meals they didn't
// (Koopman 2014), and two meals beat six of the same calories on liver fat and insulin sensitivity
// in type 2 diabetes (Kahleova 2014). The case for 3–5 hours is mostly protein: 20 g every 3 hours
// built more muscle protein than 10 g every 90 minutes or 40 g every 6 (Areta 2013), which became
// about 0.4 g/kg a meal over at least four (Schoenfeld & Aragon 2018). Over 5 hours isn't a problem
// for most people, so a long gap only gets a word in a muscle-building phase.

/// How long a gap between meals was.
public enum GapBand: String, CaseIterable, Codable, Sendable {
    /// Under 2 hours: grazing.
    case close
    /// 2 to 3 hours.
    case short
    /// 3 to 5 hours: time for blood sugar and insulin to settle, and for muscle to answer the next meal's protein.
    case spaced
    /// Over 5 hours.
    case long

    public static func of(_ interval: TimeInterval) -> GapBand {
        switch interval {
        case ..<(2 * 3600): .close
        case ..<(3 * 3600): .short
        case ...(5 * 3600): .spaced
        default: .long
        }
    }

    public var label: String {
        switch self {
        case .close: "Under 2 h"
        case .short: "2–3 h"
        case .spaced: "3–5 h"
        case .long: "Over 5 h"
        }
    }
}

/// The time between the end of one meal and the start of the next.
public struct MealGap: Hashable, Sendable {
    public var from: Date
    public var to: Date

    public init(from: Date, to: Date) {
        self.from = from
        self.to = to
    }

    public var duration: TimeInterval { to.timeIntervalSince(from) }
    public var band: GapBand { .of(duration) }
}

/// One day's eating, from 4 AM to 4 AM, so a snack after midnight belongs to the evening before.
public struct EatingDay: Hashable, Sendable {
    public var day: Day
    /// Moments of at least ``MealTiming/mealKcal``, earliest first.
    public var meals: [Moment]
    /// Between consecutive meals in the day.
    public var gaps: [MealGap]
    /// From the last meal before this day's first to that first meal; nil when the day had no meal or
    /// the days in between weren't fully logged.
    public var overnight: MealGap?
    /// From bedtime back to the last meal: negative when it was after bedtime. Nil without a meal.
    public var lastMealToBed: TimeInterval?
    /// Meals with protein enough for muscle to answer (``MealTiming/proteinPerKgPerMeal``).
    public var proteinMeals: Int

    /// First meal's start to last meal's end.
    public var window: TimeInterval? {
        guard let first = meals.first, let last = meals.last else { return nil }
        return last.end.timeIntervalSince(first.start)
    }
}

/// One thing worth changing about when meals happen.
public struct MealTimingAdvice: Hashable, Sendable {
    public enum Kind: String, Sendable { case grazing, proteinMeals, shortOvernight, lateLastMeal }

    public var kind: Kind
    public var title: String
    public var detail: String
}

/// The last week of meal timing, from the days whose log can be trusted.
public struct MealTimingReport: Hashable, Sendable {
    /// The week's trusted days with at least one meal, oldest first.
    public var days: [EatingDay]
    public var gapCounts: [GapBand: Int]
    /// Overnight fasts of up to a day (longer ones are fasts of their own).
    public var overnights: [TimeInterval]
    /// Grams of protein a meal needs to count for muscle; nil outside a muscle-building phase.
    public var proteinPerMeal: Double?
    public var advice: MealTimingAdvice?

    public static let empty = MealTimingReport(days: [], gapCounts: [:], overnights: [], proteinPerMeal: nil, advice: nil)

    /// Fewer than this many days and the week says too little.
    public static let minimumDays = 3

    public var hasEnough: Bool { days.count >= Self.minimumDays }
    public var gapCount: Int { gapCounts.values.reduce(0, +) }
    public var mealsPerDay: Double? { days.map { Double($0.meals.count) }.mean }
    public var typicalGap: TimeInterval? { days.flatMap { $0.gaps.map(\.duration) }.median }
    public var typicalOvernight: TimeInterval? { overnights.median }
    public var typicalWindow: TimeInterval? { days.compactMap(\.window).median }
    public var typicalLastMealToBed: TimeInterval? { days.compactMap(\.lastMealToBed).median }
    public var proteinMealsPerDay: Double? { proteinPerMeal == nil ? nil : days.map { Double($0.proteinMeals) }.mean }

    /// The share of the week's gaps in a band.
    public func share(_ band: GapBand) -> Double {
        gapCount == 0 ? 0 : Double(gapCounts[band] ?? 0) / Double(gapCount)
    }
}

public enum MealTiming {
    /// Under this, a moment isn't a meal and doesn't end a fast: black coffee, tea, a splash of milk.
    /// Studies of eating occasions use the same line.
    public static let mealKcal = 50.0
    /// The hour an eating day starts.
    public static let dayStartHour = 4
    /// Protein for muscle to answer a meal, per kilogram of body weight (Schoenfeld & Aragon 2018).
    public static let proteinPerKgPerMeal = 0.4
    /// An overnight fast shorter than this gets a word.
    public static let overnightAim: TimeInterval = 12 * 3600
    /// A last meal closer to bed than this gets a word.
    public static let bedtimeAim: TimeInterval = 2 * 3600
    /// The phases that build muscle, where a long gap costs a protein meal.
    public static func isBuilding(_ kind: PhaseKind?) -> Bool { kind == .leanBulk || kind == .recomp }

    /// Meals: moments of at least ``mealKcal``, earliest first.
    public static func meals(_ entries: [FoodEntry]) -> [Moment] {
        Timeline.moments(entries).filter { $0.nutrients.kcal >= mealKcal }
    }

    /// The eating day a moment belongs to: before 4 AM on the clock, the day before.
    public static func eatingDay(of date: Date, calendar: Calendar = .current) -> Day {
        let day = Day(date, calendar: calendar)
        return date < day.at(hour: dayStartHour, minute: 0, calendar: calendar) ? day.adding(days: -1) : day
    }

    /// The last meal ended at or before `now`, looking back at most `lookback`; nil when there's none.
    public static func lastMeal(before now: Date, entries: [FoodEntry], lookback: TimeInterval = 8 * 86_400) -> Moment? {
        let start = now.addingTimeInterval(-lookback)
        return meals(entries.filter { $0.date >= start && $0.date <= now }).last
    }

    /// The days in `range`, each with its meals, gaps, overnight fast and last meal before bed. A day
    /// is only read when its log is trusted (`known`: complete, fasted, or today so far), and an
    /// overnight fast only when every day it spans is. `bedtime` gives a day's bedtime; `proteinPerMeal`
    /// is the grams that count as a protein meal.
    public static func days(
        _ entries: [FoodEntry], in range: DayRange, known: Set<Day>, bedtime: (Day) -> Date, proteinPerMeal: Double?,
        calendar: Calendar = .current
    ) -> [EatingDay] {
        // A day back for the overnight fast into the first day, and a few more in case the night
        // before was a fasted day.
        let from = range.start.adding(days: -3).date(calendar: calendar)
        let to = range.end.adding(days: 1).at(hour: dayStartHour, minute: 0, calendar: calendar)
        let meals = meals(entries.filter { $0.date >= from && $0.date < to })
        // Each day's meals by their place in the whole list, so the meal before a day's first is the one before it.
        let byDay = Dictionary(grouping: meals.indices) { eatingDay(of: meals[$0].start, calendar: calendar) }
        var result: [EatingDay] = []
        for day in range.days where known.contains(day) {
            let indices = byDay[day] ?? []
            let todays = indices.map { meals[$0] }
            var gaps: [MealGap] = []
            for (a, b) in zip(todays, todays.dropFirst()) { gaps.append(MealGap(from: a.end, to: b.start)) }
            var overnight: MealGap?
            if let first = todays.first, let index = indices.first, index > 0 {
                let before = meals[index - 1]
                // Every day the fast spans was logged in full, or the meal before may just be missing.
                let spanned = DayRange(eatingDay(of: before.start, calendar: calendar), day.adding(days: -1)).days
                if spanned.allSatisfy(known.contains) { overnight = MealGap(from: before.end, to: first.start) }
            }
            let protein = proteinPerMeal.map { grams in todays.count { $0.nutrients.protein >= grams } } ?? 0
            result.append(
                EatingDay(
                    day: day, meals: todays, gaps: gaps, overnight: overnight,
                    lastMealToBed: todays.last.map { bedtime(day).timeIntervalSince($0.end) }, proteinMeals: protein))
        }
        return result
    }

    /// The week before `today`: gaps by band, overnight fasts, and the one thing worth changing.
    public static func report(
        _ entries: [FoodEntry], today: Day, known: Set<Day>, bedtime: (Day) -> Date, phase: PhaseKind?, referenceKg: Double,
        calendar: Calendar = .current
    ) -> MealTimingReport {
        let proteinPerMeal = isBuilding(phase) ? (referenceKg * proteinPerKgPerMeal / 5).rounded() * 5 : nil
        let week = DayRange(today.adding(days: -7), today.adding(days: -1))
        let days = Self.days(entries, in: week, known: known, bedtime: bedtime, proteinPerMeal: proteinPerMeal, calendar: calendar)
            .filter { !$0.meals.isEmpty }
        var counts: [GapBand: Int] = [:]
        for gap in days.flatMap(\.gaps) { counts[gap.band, default: 0] += 1 }
        let overnights = days.compactMap(\.overnight?.duration).filter { $0 <= 24 * 3600 }
        var report = MealTimingReport(days: days, gapCounts: counts, overnights: overnights, proteinPerMeal: proteinPerMeal, advice: nil)
        report.advice = advice(report)
        return report
    }

    /// The first of: grazing, too few protein meals while building muscle, a short overnight fast,
    /// eating close to bed. Nothing until the week has enough days.
    static func advice(_ r: MealTimingReport) -> MealTimingAdvice? {
        guard r.hasEnough else { return nil }
        let close = r.gapCounts[.close] ?? 0
        if close >= 3, r.share(.close) >= 1.0 / 3 {
            return MealTimingAdvice(
                kind: .grazing, title: "You often eat again within 2 hours",
                detail:
                    "\(close) of this week's \(r.gapCount) gaps between meals were under 2 hours. Folding snacks into meals 3–5 hours apart lets blood sugar and insulin settle between them; in one trial, the same extra calories as snacks raised liver fat where with meals they didn't."
            )
        }
        if let grams = r.proteinPerMeal, let perDay = r.proteinMealsPerDay, perDay < 3 {
            return MealTimingAdvice(
                kind: .proteinMeals, title: "Spread protein over more meals",
                detail:
                    "Muscle answers each meal's protein for a few hours. About \(Int(grams)) g in 3–5 meals, 3–5 hours apart, builds more than the same protein in fewer; this week averaged \(Self.one(perDay)) a day."
            )
        }
        if r.overnights.count >= MealTimingReport.minimumDays, let overnight = r.typicalOvernight, overnight < overnightAim {
            return MealTimingAdvice(
                kind: .shortOvernight, title: "Overnight fast about \(Self.hours(overnight))",
                detail:
                    "Most people eat across about 15 hours a day. 12 hours or more from dinner to breakfast is an easy habit: finish dinner a little earlier, or have breakfast a little later."
            )
        }
        if let toBed = r.typicalLastMealToBed, toBed < bedtimeAim {
            return MealTimingAdvice(
                kind: .lateLastMeal, title: "Eating close to bed",
                detail:
                    "Your last meal is usually within 2 hours of bedtime. Eating late leaves people hungrier the next day and burning a little less; finishing 2–3 hours before bed is the aim."
            )
        }
        return nil
    }

    /// "10½ h", "13 h".
    public static func hours(_ interval: TimeInterval) -> String {
        let halves = (interval / 1800).rounded()
        let whole = Int(halves / 2)
        return halves.truncatingRemainder(dividingBy: 2) == 0 ? "\(whole) h" : "\(whole)½ h"
    }

    private static func one(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
}

extension Array where Element == Double {
    /// The middle value (the mean of the middle two for an even count); nil when empty.
    var median: Double? {
        guard !isEmpty else { return nil }
        let sorted = sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
