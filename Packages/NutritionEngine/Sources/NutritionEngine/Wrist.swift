import Foundation
import SystemCore

// What the Watch shows: today's numbers against the targets the phone shows, the usual foods to log
// again, water, the doses due now, the weigh-in dial, and the snapshot its complications read. All of
// it comes from the `MacroAnalysis` the phone runs, over the same records, so the wrist and the phone
// can't disagree.

/// One macro so far today against its target, when the day has one.
public struct MacroProgress: Hashable, Codable, Sendable {
    public var eaten: Double
    public var target: Double?

    public init(eaten: Double, target: Double?) {
        self.eaten = eaten
        self.target = target
    }

    /// What's left, negative once over; nil without a target.
    public var left: Double? { target.map { $0 - eaten } }

    /// How full the ring is, 0 to 1: past the target it stays full. Nil without a target.
    public var fraction: Double? {
        guard let target else { return nil }
        guard target > 0 else { return eaten > 0 ? 1 : 0 }
        return min(1, max(0, eaten / target))
    }

    /// Past the target by a whole unit or more, so 0.4 kcal over still reads as on target.
    public var isOver: Bool { (left ?? 0) <= -1 }
}

/// A quick add of water: a glass and a bottle.
public struct WaterGlass: Hashable, Sendable, Identifiable {
    public var label: String
    public var ml: Double

    public init(label: String, ml: Double) {
        self.label = label
        self.ml = ml
    }

    public var id: String { label }
}

extension Hydration {
    /// A glass and a bottle in the person's units: fluid ounces for people who weigh in pounds.
    public static func glasses(fluidOunces: Bool) -> [WaterGlass] {
        fluidOunces
            ? [WaterGlass(label: "8 oz", ml: 236.6), WaterGlass(label: "16.9 oz", ml: 500)]
            : [WaterGlass(label: "Glass", ml: 250), WaterGlass(label: "Bottle", ml: 500)]
    }
}

extension SupplementPlan {
    /// The doses to offer now, earliest first: the open ones whose time of day has come (the time
    /// nearest now, and any earlier one still unmarked). `later` counts the open ones still to come.
    public static func dueNow(_ doses: [DueDose], minutes: Int, times: [DoseTime: Int] = [:]) -> (now: [DueDose], later: Int) {
        let current = DoseTime.nearest(minutes: minutes, times: times)
        let open = doses.filter(\.open)
        return (open.filter { $0.dose.time <= current }, open.count { $0.dose.time > current })
    }
}

/// The weigh-in on the Digital Crown: the person's unit, the step one detent moves (0.1 kg or
/// 0.2 lb, as on the phone), the ends a plausible weight lies between, and where it starts.
public struct WeighInDial: Hashable, Sendable {
    public var unit: WeightUnit
    public var step: Double
    public var range: ClosedRange<Double>
    /// The last weigh-in on the step's grid, or a typical weight for the person's sex before the first.
    public var start: Double

    public init(unit: WeightUnit, latestKg: Double?, sex: BiologicalSex) {
        self.unit = unit
        let step = unit == .lb ? 0.2 : 0.1
        self.step = step
        // Inside the plausible weights (`Weight.isPlausible`), never on their edges.
        let low = ((unit.fromKilograms(20) / step + 1e-9).rounded(.down) + 1) * step
        let high = ((unit.fromKilograms(400) / step - 1e-9).rounded(.up) - 1) * step
        range = Self.tidy(low)...Self.tidy(high)
        let kg = latestKg.flatMap { Weight.isPlausible(kg: $0) ? $0 : nil } ?? (sex == .female ? 68 : 82)
        start = min(range.upperBound, max(range.lowerBound, Self.tidy((unit.fromKilograms(kg) / step).rounded() * step)))
    }

    /// A dial value on the step's grid, clamped to the range: the crown can land between detents.
    public func snapped(_ value: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, Self.tidy((value / step).rounded() * step)))
    }

    /// The kilograms a dial value saves as.
    public func kilograms(_ value: Double) -> Double { unit.toKilograms(snapped(value)) }

    /// Rounded to a tenth, so 0.1 × 3 reads 0.3 and not 0.30000000000000004.
    private static func tidy(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}

/// Today on the wrist, from the phone's analysis.
public struct WristToday: Hashable, Sendable {
    public var day: Day
    public var mode: DailyTargets.Mode
    /// "Day 5 of 21", "Diet break", "Cut": what the day is, as the widgets say it.
    public var badge: String?
    public var note: String
    public var kcal: MacroProgress
    public var protein: MacroProgress
    public var carbs: MacroProgress
    public var fat: MacroProgress
    /// Carbs and fat shown too, or only calories and protein (a setting).
    public var showsAllMacros: Bool
    /// What was eaten around now on a recent day, while nothing's logged near now today.
    public var sameAsUsual: Moment?
    /// Single foods to log again, best first, as the phone ranks them.
    public var logAgain: [LogAgainItem]
    /// Water and drinks so far against the day's aim; nil when drinks aren't tracked.
    public var water: HydrationDay?
    public var glasses: [WaterGlass]
    /// Open doses whose time has come, earliest first, and how many more are due later today.
    public var doses: [DueDose]
    public var laterDoses: Int
    /// Every dose planned today, marked or not: whether the day has supplements at all.
    public var dosesToday: Int
    public var dial: WeighInDial
    public var weighedToday: Bool
    public var dayState: DayState?
    public var hasEntries: Bool
    /// Meal timing and fasting turned on, the fast running, and when the last meal ended (what the
    /// time since counts from when no fast runs).
    public var tracksMealTiming: Bool
    public var fast: FastStatus?
    public var lastMealEnd: Date?
    /// Where a fast started now would start: the end of the last meal in the last day, else now.
    public var suggestedFastStart: Date

    /// How many single foods to offer: what the phone's Log again row shows.
    public static let logAgainCount = 10

    public init(state: MacroState, analysis: MacroAnalysis, calendar: Calendar = .current) {
        let today = state.today
        let targets = analysis.targets
        let eaten = analysis.intakeByDay[today] ?? .zero
        day = today
        mode = targets.mode
        badge = Self.badge(targets, assessment: analysis.assessment, phase: analysis.phase)
        note = targets.note
        kcal = MacroProgress(eaten: eaten.kcal, target: targets.kcal)
        protein = MacroProgress(eaten: eaten.protein, target: targets.protein)
        carbs = MacroProgress(eaten: eaten.carbs, target: targets.carbs)
        fat = MacroProgress(eaten: eaten.fat, target: targets.fat)
        showsAllMacros = state.settings.showAllMacros
        sameAsUsual = LogAgain.usualNow(entries: state.entries, now: state.now, calendar: calendar)
        logAgain = LogAgain.rank(state.entries, now: state.now, calendar: calendar, limit: Self.logAgainCount)
        water = state.settings.drinks ? analysis.hydration : nil
        glasses = Hydration.glasses(fluidOunces: state.profile.units.weight == .lb)
        let training = SupplementPlan.isTrainingDay(today, profile: state.profile, lift: state.lift)
        let due = SupplementPlan.due(on: today, stack: state.supplements, logs: state.supplementLogs, training: training)
        let clock = calendar.dateComponents([.hour, .minute], from: state.now)
        let now = SupplementPlan.dueNow(due, minutes: (clock.hour ?? 0) * 60 + (clock.minute ?? 0), times: state.settings.doseTimes ?? [:])
        doses = now.now
        laterDoses = now.later
        dosesToday = due.count
        let latest = state.weighIns.filter(Weight.counts).max { $0.date < $1.date }
        dial = WeighInDial(unit: state.profile.units.weight, latestKg: latest?.kg, sex: state.profile.sex)
        weighedToday = state.weighIns.contains { $0.day == today }
        dayState = state.dayStatus.first { $0.day == today }?.state
        hasEntries = state.entries.contains { $0.day == today }
        tracksMealTiming = state.settings.mealTiming
        fast = analysis.fast
        lastMealEnd = analysis.lastMeal?.end
        suggestedFastStart = Fasting.suggestedStart(entries: state.entries.filter { $0.day >= today.adding(days: -2) }, now: state.now)
    }

    /// The day in a word or two: the assessment's progress, a life mode, or the phase.
    public static func badge(_ targets: DailyTargets, assessment: AssessmentProgress?, phase: PlannedPhase?) -> String? {
        switch targets.mode {
        case .assessment: assessment.map { "Day \($0.day) of \($0.totalDays)" } ?? "Assessment"
        case .dietBreak: "Diet break"
        case .crunch: "Crunch"
        case .illness: "Ill"
        case .vacation: "Vacation"
        case .phase: phase?.kind.label
        }
    }
}

/// What the Watch's complications show: calories and protein so far against today's targets.
/// The Watch app writes it into its App Group whenever the numbers change, so they draw without
/// opening the database.
public struct WristSnapshot: Codable, Hashable, Sendable {
    public var day: Day
    public var kcal: MacroProgress
    public var protein: MacroProgress
    public var badge: String?
    /// The fast running when it was written, for the fasting complication; nil without one. Older
    /// snapshots don't have them.
    public var fastStart: Date?
    public var fastGoalHours: Double?
    /// When the last meal ended, while meal timing is on, for the time since it.
    public var lastMealEnd: Date?
    public var updated: Date

    public init(
        day: Day, kcal: MacroProgress, protein: MacroProgress, badge: String? = nil, fastStart: Date? = nil, fastGoalHours: Double? = nil,
        lastMealEnd: Date? = nil, updated: Date = Date()
    ) {
        self.day = day
        self.kcal = kcal
        self.protein = protein
        self.badge = badge
        self.fastStart = fastStart
        self.fastGoalHours = fastGoalHours
        self.lastMealEnd = lastMealEnd
        self.updated = updated
    }

    public init(_ today: WristToday, updated: Date = Date()) {
        self.init(
            day: today.day, kcal: today.kcal, protein: today.protein, badge: today.badge,
            fastStart: today.tracksMealTiming ? today.fast?.fast.start : nil,
            fastGoalHours: today.tracksMealTiming ? today.fast?.fast.goalHours : nil,
            lastMealEnd: today.tracksMealTiming ? today.lastMealEnd : nil, updated: updated)
    }

    /// The fast as it stands at `date`, for a complication's timeline entry.
    public func fast(at date: Date) -> FastStatus? {
        guard let fastStart, let fastGoalHours else { return nil }
        return Fasting.status(Fast(start: fastStart, goalHours: fastGoalHours), now: date)
    }

    /// Before the Watch app has written one: nothing eaten, no targets.
    public static let empty = WristSnapshot(
        day: Day(ordinal: 0), kcal: MacroProgress(eaten: 0, target: nil), protein: MacroProgress(eaten: 0, target: nil),
        updated: .distantPast)

    /// For the watch face's gallery.
    public static func sample(on day: Day) -> WristSnapshot {
        WristSnapshot(
            day: day, kcal: MacroProgress(eaten: 1_240, target: 2_300), protein: MacroProgress(eaten: 96, target: 170), badge: "Cut")
    }

    /// As it stands on `day`: past the day it was written for, nothing's eaten yet (the targets
    /// carry over until the app writes the new day's).
    public func shown(on day: Day) -> WristSnapshot {
        guard day != self.day else { return self }
        var fresh = self
        fresh.day = day
        fresh.kcal.eaten = 0
        fresh.protein.eaten = 0
        return fresh
    }

    /// Whether the numbers differ from `other`'s, ignoring when each was written.
    public func differs(from other: WristSnapshot) -> Bool {
        var a = self
        var b = other
        a.updated = .distantPast
        b.updated = .distantPast
        return a != b
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }

    /// The snapshot in `data`; nil when it isn't one (written by another build, say).
    public static func decoded(_ data: Data) -> WristSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(WristSnapshot.self, from: data)
    }
}
