import Foundation
import SystemCore

// Fasts the person starts on purpose, with a goal: from a 13-hour night to a few days. A fast ends
// when it's ended or when a meal is logged after it began (on any device), so an Undo of that meal
// puts the fast back. Its phases are what's reasonably established in people, as ranges, with what
// moves them; the hour-by-hour claims some apps make (autophagy at 16 hours) come from mice.

/// A fast with a goal.
public struct Fast: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var start: Date
    public var goalHours: Double
    /// When it was ended by hand; nil while it runs, or when a meal ended it.
    public var end: Date?
    public var updatedAt: Date

    public init(id: UUID = UUID(), start: Date, goalHours: Double, end: Date? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.start = start
        self.goalHours = goalHours
        self.end = end
        self.updatedAt = updatedAt
    }

    public var goalEnd: Date { start.addingTimeInterval(goalHours * 3600) }
}

/// What's likely happening, hours into a fast (or since the last meal).
public enum FastPhase: Int, CaseIterable, Codable, Sendable, Comparable {
    case digesting, insulinLow, fatBurning, ketosis, deepKetosis

    /// Hours after the last meal it begins.
    public var startHours: Double {
        switch self {
        case .digesting: 0
        case .insulinLow: 4
        case .fatBurning: 12
        case .ketosis: 24
        case .deepKetosis: 72
        }
    }

    public var title: String {
        switch self {
        case .digesting: "Digesting"
        case .insulinLow: "Insulin low"
        case .fatBurning: "Fat burning"
        case .ketosis: "Ketosis"
        case .deepKetosis: "Deep ketosis"
        }
    }

    public var hoursLabel: String {
        switch self {
        case .digesting: "0–4 h"
        case .insulinLow: "4–12 h"
        case .fatBurning: "12–24 h"
        case .ketosis: "1–3 days"
        case .deepKetosis: "3 days +"
        }
    }

    public var detail: String {
        switch self {
        case .digesting:
            "Blood sugar and insulin rise with the meal and settle over 2–4 hours; a big or fatty meal takes longer."
        case .insulinLow:
            "Insulin is low and the liver's glycogen keeps blood sugar steady. Fat burning picks up as the hours pass. Most overnight fasts end here."
        case .fatBurning:
            "Fat is now the main fuel. The liver's glycogen runs low by about a day in, and ketones start to rise: sooner after training or a low-carb meal."
        case .ketosis:
            "The liver makes ketones and new glucose. Growth hormone rises several-fold, metabolic rate holds or rises slightly, and hunger usually peaks on day 2, then eases. Sodium, potassium and magnesium matter now."
        case .deepKetosis:
            "Ketones keep climbing and the brain runs more on them, so protein breakdown slows. Past 5 days, breaking the fast needs care, best with a doctor."
        }
    }

    public var symbol: String {
        switch self {
        case .digesting: "fork.knife"
        case .insulinLow: "drop"
        case .fatBurning: "flame"
        case .ketosis: "bolt.heart"
        case .deepKetosis: "sparkles"
        }
    }

    public var next: FastPhase? { FastPhase(rawValue: rawValue + 1) }

    public static func at(hours: Double) -> FastPhase {
        allCases.last { hours >= $0.startHours } ?? .digesting
    }

    public static func < (a: FastPhase, b: FastPhase) -> Bool { a.rawValue < b.rawValue }

    /// What the timings don't say, for under the phases.
    public static let caveat =
        "The hours are typical, not exact: a big or carb-heavy last meal pushes them later, and training, a low-carb diet or being lean brings them earlier. Autophagy timed to the hour comes from mice; nobody has measured when it rises in people."
}

/// A fast as it ran: when it ended (by hand or by a meal), or nil while it runs. Its `fast` starts
/// where the fasting did: after the meal it began from, if food was added to that meal.
public struct FastRun: Hashable, Sendable, Identifiable {
    public var fast: Fast
    public var end: Date?
    /// Ended by hand: the person was there to say so. A fast a meal ended, or one left running past
    /// its goal, is vouched for only to its goal (``vouched(at:)``).
    public var endedByHand: Bool

    public init(fast: Fast, end: Date?, endedByHand: Bool = false) {
        self.fast = fast
        self.end = end
        self.endedByHand = endedByHand
    }

    public var id: UUID { fast.id }
    public var isRunning: Bool { end == nil }

    /// How long it ran, as shown.
    public func duration(at now: Date) -> TimeInterval { max(0, (end ?? now).timeIntervalSince(fast.start)) }

    /// How long the record can vouch for: past its goal, a meal logged later may only mean meals
    /// weren't logged, so only a fast ended by hand counts beyond it. What a fast does to the scale,
    /// the estimate and the fasted days goes by this.
    public func vouched(at now: Date) -> TimeInterval {
        let to = end ?? now
        return max(0, (endedByHand ? to : min(to, fast.goalEnd)).timeIntervalSince(fast.start))
    }
}

/// Long fasts as the maintenance estimate sees them (``Fasting/adjustment(_:usable:maintenance:today:now:calendar:)``).
public struct FastAdjustment: Hashable, Sendable {
    public struct Deficit: Hashable, Sendable {
        public var start: Date
        public var kg: Double
    }

    public var excluded: Set<Day>
    public var deficits: [Deficit]

    public var isEmpty: Bool { excluded.isEmpty }

    /// The weigh-ins with each fast's deficit taken off those before it.
    public func adjusted(_ weighIns: [WeighIn]) -> [WeighIn] {
        guard !deficits.isEmpty else { return weighIns }
        return weighIns.map { w in
            var w = w
            w.kg -= deficits.filter { w.date < $0.start }.map(\.kg).reduce(0, +)
            return w
        }
    }
}

/// A running fast, now.
public struct FastStatus: Hashable, Sendable {
    public var fast: Fast
    public var elapsed: TimeInterval
    public var phase: FastPhase
    /// When the next phase begins; nil in the last one.
    public var nextPhaseAt: Date?

    public var hours: Double { elapsed / 3600 }
    /// Toward the goal: past 1 once it's reached.
    public var progress: Double { fast.goalHours > 0 ? hours / fast.goalHours : 1 }
    public var goalReached: Bool { hours >= fast.goalHours }
    public var remaining: TimeInterval { max(0, fast.goalHours * 3600 - elapsed) }
}

/// A moment in a fast worth a notification: a new phase, or the goal.
public struct FastMilestone: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case phase(FastPhase)
        case goal
    }

    public var kind: Kind
    public var at: Date
    public var title: String
    public var body: String
}

public enum Fasting {
    /// The goals offered with one tap.
    public static let presets: [Double] = [13, 16, 18, 24, 36, 48, 72]
    /// The longest goal the app sets: a week.
    public static let maxHours = 168.0
    /// Past this, a fast's scale readings are mostly water and glycogen, and the days after are
    /// left out of the trend.
    public static let longHours = 24.0
    /// Days after a long fast whose weigh-ins are still refilling glycogen and water.
    public static let refillDays = 3
    /// A fast with no meal logged this long past its goal is taken as over at its goal: it was
    /// likely forgotten, or meals went unlogged.
    public static let forgottenAfterGoal: TimeInterval = 12 * 3600

    /// Each fast with when it ended: by hand, or at the first meal logged after it began; one left
    /// with no meal well past its goal ends at its goal. Food added to the meal a fast began from
    /// (within ``Timeline/gap`` of it, as dessert after dinner) moves the start to after it rather
    /// than ending it. Each fast reads only the entries around it, so years of fasts and entries
    /// cost a search each.
    public static func runs(_ fasts: [Fast], entries: [FoodEntry], now: Date) -> [FastRun] {
        guard !fasts.isEmpty else { return [] }
        let sorted = entries.sorted { $0.date < $1.date }
        let gap = Timeline.gap
        return fasts.sorted { $0.start < $1.start }.map { stored in
            var fast = stored
            // The first entry after the start.
            var i = firstIndex(in: sorted, after: fast.start)
            // Food chained to a meal eaten before the start is that meal running on.
            if i < sorted.count, i > 0, sorted[i].date.timeIntervalSince(sorted[i - 1].date) <= gap {
                var before = sorted[i - 1].nutrients.kcal
                var j = i - 1
                while j > 0, sorted[j].date.timeIntervalSince(sorted[j - 1].date) <= gap {
                    j -= 1
                    before += sorted[j].nutrients.kcal
                }
                var k = i
                var after = sorted[i].nutrients.kcal
                while k + 1 < sorted.count, sorted[k + 1].date.timeIntervalSince(sorted[k].date) <= gap {
                    k += 1
                    after += sorted[k].nutrients.kcal
                }
                if after >= MealTiming.mealKcal, before >= MealTiming.mealKcal, stored.end.map({ sorted[k].date < $0 }) ?? true {
                    fast.start = sorted[k].date
                    i = k + 1
                }
            }
            let meal = firstMeal(in: sorted, from: i, gap: gap)
            let limit = fast.goalEnd.addingTimeInterval(forgottenAfterGoal)
            var end: Date?
            var byHand = false
            if let hand = stored.end, hand <= meal ?? .distantFuture {
                end = max(fast.start, hand)
                byHand = true
            } else if let meal, meal <= limit {
                end = meal
            } else if (meal ?? now) > limit, now > limit {
                end = fast.goalEnd
            }
            return FastRun(fast: fast, end: end.flatMap { $0 <= now ? $0 : nil }, endedByHand: byHand)
        }
    }

    /// The index of the first entry after `date` in entries sorted by date.
    private static func firstIndex(in sorted: [FoodEntry], after date: Date) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid].date > date { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// When the first meal from `index` on began: the first run of entries each within `gap` of the
    /// last that adds up to a meal.
    private static func firstMeal(in sorted: [FoodEntry], from index: Int, gap: TimeInterval) -> Date? {
        var i = index
        while i < sorted.count {
            var kcal = sorted[i].nutrients.kcal
            var k = i
            while k + 1 < sorted.count, sorted[k + 1].date.timeIntervalSince(sorted[k].date) <= gap {
                k += 1
                kcal += sorted[k].nutrients.kcal
            }
            if kcal >= MealTiming.mealKcal { return sorted[i].date }
            i = k + 1
        }
        return nil
    }

    /// The fast running now: the latest one not ended.
    public static func active(_ runs: [FastRun]) -> FastRun? { runs.last { $0.isRunning } }

    public static func status(_ fast: Fast, now: Date) -> FastStatus {
        let elapsed = max(0, now.timeIntervalSince(fast.start))
        let phase = FastPhase.at(hours: elapsed / 3600)
        return FastStatus(
            fast: fast, elapsed: elapsed, phase: phase, nextPhaseAt: phase.next.map { fast.start.addingTimeInterval($0.startHours * 3600) })
    }

    /// Where a new fast starts: the end of the last meal, when that was in the last day, else now.
    public static func suggestedStart(entries: [FoodEntry], now: Date) -> Date {
        MealTiming.lastMeal(before: now, entries: entries, lookback: 86_400)?.end ?? now
    }

    /// Whole calendar days inside fasts, before `today`, as far as each is vouched for: they count as
    /// fasted days without being marked (complete, at what was drunk), and with the fast's other days
    /// leave what the estimate learns from (``adjustment(_:usable:maintenance:today:now:calendar:)``).
    public static func fastedDays(_ runs: [FastRun], today: Day, now: Date, calendar: Calendar = .current) -> Set<Day> {
        var days = Set<Day>()
        for run in runs {
            let covered = run.fast.start.addingTimeInterval(run.vouched(at: now))
            guard covered.timeIntervalSince(run.fast.start) >= 86_400 else { continue }
            var day = Day(run.fast.start, calendar: calendar).adding(days: 1)
            // The first whole day after the start; one starting at midnight is whole itself.
            if run.fast.start <= Day(run.fast.start, calendar: calendar).date(calendar: calendar) { day = Day(run.fast.start, calendar: calendar) }
            while day < today, day.adding(days: 1).date(calendar: calendar) <= covered {
                days.insert(day)
                day = day.adding(days: 1)
            }
        }
        return days
    }

    /// Days whose weigh-ins a long fast skews: from the day after it began to a few days after it
    /// ended (the water and glycogen come back with food). The fast's days still count for intake.
    public static func waterDays(_ runs: [FastRun], now: Date, calendar: Calendar = .current) -> Set<Day> {
        var days = Set<Day>()
        for run in runs where run.vouched(at: now) >= longHours * 3600 {
            let first = Day(run.fast.start, calendar: calendar).adding(days: 1)
            let last = Day(run.end ?? now, calendar: calendar).adding(days: refillDays)
            for day in DayRange(first, last).days { days.insert(day) }
        }
        return days
    }

    /// What the maintenance estimate and the check-in learn from around long fasts. Each fast's days
    /// and the refill days after it are left out, intake and scale alike, and the energy it went
    /// without is taken off the weigh-ins before it, so the weeks around it read as if those days
    /// were eaten at maintenance: neither the water swing nor the step between the readings before
    /// and after can move the estimate. `maintenance` is the estimate before it (the check-in's).
    public static func adjustment(_ runs: [FastRun], usable: [Day: Double], maintenance: Double, today: Day, now: Date, calendar: Calendar = .current)
        -> FastAdjustment
    {
        var excluded = Set<Day>()
        var deficits: [FastAdjustment.Deficit] = []
        for run in runs where run.vouched(at: now) >= longHours * 3600 {
            let days = waterDays([run], now: now, calendar: calendar)
            excluded.formUnion(days)
            // A day without a full log is taken as eaten at maintenance.
            let kcal = days.filter { $0 < today }.map { maintenance - (usable[$0] ?? maintenance) }.reduce(0, +)
            deficits.append(FastAdjustment.Deficit(start: run.fast.start, kg: kcal / Energy.kcalPerKg))
        }
        return FastAdjustment(excluded: excluded, deficits: deficits)
    }

    /// A long fast running, or one that ended in the last few days: the check-in holds until the
    /// scale settles.
    public static func recentLongFast(_ runs: [FastRun], today: Day, now: Date, calendar: Calendar = .current) -> FastRun? {
        runs.last { run in
            run.vouched(at: now) >= longHours * 3600
                && (run.end.map { Day($0, calendar: calendar).adding(days: refillDays) >= today } ?? true)
        }
    }

    /// The fast's notifications: each phase it reaches before its goal (from 12 hours on), and the goal.
    public static func milestones(_ fast: Fast) -> [FastMilestone] {
        var list: [FastMilestone] = []
        for phase in FastPhase.allCases where phase.startHours >= 12 && phase.startHours < fast.goalHours {
            var body = phase.detail
            if phase == .ketosis, let salt = FastSafety.electrolytes(hours: phase.startHours) { body = salt }
            list.append(
                FastMilestone(
                    kind: .phase(phase), at: fast.start.addingTimeInterval(phase.startHours * 3600),
                    title: "\(MealTiming.hours(phase.startHours * 3600)) in: \(phase.title.lowercased())", body: body))
        }
        list.append(
            FastMilestone(
                kind: .goal, at: fast.goalEnd, title: "\(MealTiming.hours(fast.goalHours * 3600)) fast done",
                body: FastSafety.refeed(hours: fast.goalHours) ?? "Your goal's reached. End the fast when you eat; logging a meal ends it too."))
        return list
    }
}

/// Who shouldn't fast for long, when to stop, and how to break a long fast.
public enum FastSafety {
    /// Goals longer than this need the safety screen read once.
    public static let screenHours = 24.0
    /// Past this, a doctor's supervision is the advice.
    public static let supervisedHours = 72.0

    /// Fasts over a day aren't for these; the app can check age and weight, the person the rest.
    public static let whoShouldnt = [
        "Diabetes treated with insulin or a sulfonylurea (gliclazide, glipizide): blood sugar can fall dangerously.",
        "An SGLT2 inhibitor (empagliflozin, dapagliflozin): fasting can bring on ketoacidosis.",
        "Pregnancy or breastfeeding.",
        "An eating disorder, now or in the past.",
        "Under 18, or underweight.",
        "Gout, or medicines for blood pressure or the heart: ask your doctor first.",
    ]

    /// Signs to stop a fast and eat.
    public static let stopIf = [
        "Dizzy or faint on standing", "Heart racing or skipping", "Confused, or unusually weak", "Vomiting, or unable to keep water down",
    ]

    /// Why a fast over a day isn't offered to this person; nil when it is.
    public enum Block: Hashable, Sendable {
        case under18
        case underweight(bmi: Double)

        public var reason: String {
            switch self {
            case .under18: "Fasts over a day aren't offered under 18: growing bodies need regular meals."
            case .underweight(let bmi):
                "Fasts over a day aren't offered at a BMI of \(bmi.formatted(.number.precision(.fractionLength(1)))): there's too little in reserve."
            }
        }
    }

    public static func block(profile: SharedProfile, weightKg: Double?, today: Day) -> Block? {
        if let age = profile.age(on: today), age < 18 { return .under18 }
        if let kg = weightKg, let cm = profile.heightCm, cm > 0 {
            let bmi = kg / pow(cm / 100, 2)
            if bmi < 18.5 { return .underweight(bmi: bmi) }
        }
        return nil
    }

    /// The longest goal this person can set.
    public static func longest(_ block: Block?) -> Double { block == nil ? Fasting.maxHours : screenHours }

    /// Salt and minerals, once a fast passes a day.
    public static func electrolytes(hours: Double) -> String? {
        hours >= 24
            ? "Past a day, sodium, potassium and magnesium matter: water with a pinch of salt helps, and dizziness on standing is the sign you need more."
            : nil
    }

    /// How to break a fast this long; nil when an ordinary meal is fine.
    public static func refeed(hours: Double) -> String? {
        switch hours {
        case 120...:
            "After 5 days or more, eat small and slowly and ask a doctor first: a sudden return to food can drop phosphate, potassium and magnesium dangerously (refeeding syndrome)."
        case 48...:
            "Break it with something small and easy (eggs, yogurt, soup), then an ordinary meal a couple of hours later."
        case 24...:
            "Break it with an ordinary meal with protein, not a feast: a big meal after a long fast often sits badly."
        default:
            nil
        }
    }

    /// What a goal this long works against: the plan's phase, or a fast past the point a doctor should be involved.
    public static func notes(goalHours: Double, phase: PhaseKind?) -> [String] {
        var notes: [String] = []
        if goalHours > supervisedHours {
            notes.append("Fasts over 3 days are best done with a doctor who knows: they can check your minerals and medicines.")
        }
        if goalHours >= Fasting.longHours, MealTiming.isBuilding(phase), let phase {
            notes.append("A fast this long works against the \(phase.label.lowercased()): a day without protein is a day without building.")
        }
        return notes
    }
}
