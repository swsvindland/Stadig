import Foundation
import SystemCore

/// Everything Macro Track knows, as plain values.
public struct MacroState: Sendable {
    public var profile: SharedProfile
    public var settings: MacroSettings
    public var entries: [FoodEntry]
    public var weighIns: [WeighIn]
    public var dayStatus: [DayStatus]
    public var plan: PhasePlan?
    public var lifeModes: [LifeModePeriod]
    /// The training calendar Lift Track publishes, for system-wide deloads.
    public var calendar: SystemCalendar?
    /// Lift Track's summary, when it's installed: strength, measurements, training days.
    public var lift: AppSummary?
    /// Weekly check-ins, oldest first: the targets in force from each day on.
    public var checkIns: [CheckIn]
    /// The supplement stack, and doses taken or skipped.
    public var supplements: [Supplement]
    public var supplementLogs: [SupplementLog]
    public var water: [WaterLog]
    public var today: Day

    public init(profile: SharedProfile, settings: MacroSettings, entries: [FoodEntry] = [], weighIns: [WeighIn] = [],
                dayStatus: [DayStatus] = [], plan: PhasePlan? = nil, lifeModes: [LifeModePeriod] = [], calendar: SystemCalendar? = nil,
                lift: AppSummary? = nil, checkIns: [CheckIn] = [], supplements: [Supplement] = [], supplementLogs: [SupplementLog] = [],
                water: [WaterLog] = [], today: Day = .today) {
        self.profile = profile
        self.settings = settings
        self.entries = entries
        self.weighIns = weighIns
        self.dayStatus = dayStatus
        self.plan = plan
        self.lifeModes = lifeModes
        self.calendar = calendar
        self.lift = lift
        self.checkIns = checkIns.sorted { $0.day < $1.day }
        self.supplements = supplements
        self.supplementLogs = supplementLogs
        self.water = water
        self.today = today
    }

    /// Bedtime on a day, from the person's bedtime (after midnight counts as that night).
    public func bedtime(on day: Day, calendar: Calendar = .current) -> Date {
        let minutes = settings.minutes(.bedtime)
        let night = minutes < 12 * 60 ? day.adding(days: 1) : day
        return night.date(calendar: calendar).addingTimeInterval(Double(minutes % (24 * 60)) * 60)
    }
}

public struct AssessmentProgress: Hashable, Sendable {
    public var day: Int
    public var totalDays: Int
    public var learned: [String]
    public var complete: Bool
    public var progress: Double { Double(min(day, totalDays)) / Double(max(1, totalDays)) }
}

/// A prescriptive insight: what was seen, then the one thing to do.
public struct MacroAction: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case weighIn, protein, logYesterday, planReady, whoosh, reviewPlan, weighInSoon }

    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var action: String
    public var priority: Double
}

public struct MacroAnalysis: Sendable {
    public var trend: WeightTrend
    public var weeklyChange: Double?
    public var maintenance: MaintenanceEstimate
    public var assessment: AssessmentProgress?
    public var plan: PhasePlan?
    public var phase: PlannedPhase?
    public var targets: DailyTargets
    public var todayIntake: Nutrients
    public var intakeByDay: [Day: Nutrients]
    public var discipline: DisciplineScore
    /// Logged days over expected days in the last four weeks: the habit, separate from targets.
    public var loggingRate: Double?
    public var actions: [MacroAction]
    public var life: LifeModeEffects
    public var plannerInput: PlannerInput
    /// Days that teach the estimate: complete (or fasting) with their calories.
    public var usable: [Day: Double]
    /// The check-in in force today, and a new one when this week's is due.
    public var checkIn: CheckIn?
    public var dueCheckIn: CheckIn?
    /// Body weight to scale targets by.
    public var referenceKg: Double
    /// Vitamins and minerals over the last week of complete days.
    public var micros: MicroReport = .empty
    /// Whole against ultra-processed, and fermented foods, over the same days.
    public var quality: QualityReport = .empty
    /// Today's caffeine and drinks.
    public var caffeine: CaffeineReport?
    public var hydration: HydrationDay?

    public var remaining: Nutrients? {
        guard let kcal = targets.kcal else { return nil }
        return Nutrients(kcal: kcal - todayIntake.kcal, protein: (targets.protein ?? 0) - todayIntake.protein,
                         carbs: (targets.carbs ?? 0) - todayIntake.carbs, fat: (targets.fat ?? 0) - todayIntake.fat)
    }
}

public enum MacroAnalyst {
    /// Assessment length: three weeks, two when Health already had a fortnight of weigh-ins.
    public static func assessmentDays(weighInsBeforeStart: Int) -> Int { weighInsBeforeStart >= 10 ? 14 : 21 }

    public static func analyse(_ state: MacroState) -> MacroAnalysis {
        let today = state.today
        // Days just back from a trip or illness are water: they don't move the trend.
        var ignored = Set<Day>()
        for period in state.lifeModes {
            switch period.kind {
            case .vacation, .illness:
                if let end = period.end {
                    for d in 0...LifeModes.reentryDays { ignored.insert(end.adding(days: d)) }
                }
                for d in period.range(openUntil: today).days { ignored.insert(d) }
            default:
                break
            }
        }
        let trend = Weight.trend(state.weighIns, through: today, ignored: ignored)
        let weight = trend.latest?.trend ?? state.weighIns.last?.kg ?? (state.profile.sex == .female ? 68 : 82)

        // Intake per day, and which days count as fully logged.
        var intakeByDay: [Day: Nutrients] = [:]
        for entry in state.entries { intakeByDay[entry.day] = (intakeByDay[entry.day] ?? .zero) + entry.nutrients }
        // A supplement's few calories count on days with food logged; alone, they don't make a day logged.
        for log in state.supplementLogs where log.taken {
            if let n = log.nutrients, let day = intakeByDay[log.day] {
                intakeByDay[log.day] = day + Nutrients(kcal: n.kcal, protein: n.protein, carbs: n.carbs, fat: n.fat)
            }
        }

        let trainingDays = state.lift.map { summary in
            Int((Double(summary.sessions.filter { $0.kind == .strength && $0.day > today.adding(days: -28) }.count) / 4).rounded())
        } ?? state.profile.schedule.daysPerWeek
        let otherMinutes = Double(state.lift?.sessions.filter { $0.kind == .activity && $0.day > today.adding(days: -28) }.map(\.minutes).reduce(0, +) ?? 0) / 4
            + Double(state.profile.recurring.map { $0.minutes * $0.weekdays.count }.reduce(0, +))
        let formula = Energy.formula(sex: state.profile.sex, kg: weight, heightCm: state.profile.heightCm, age: state.profile.age(on: today),
                                     trainingDays: trainingDays, otherActiveMinutes: otherMinutes)
        // Usable days: marked complete (or fasting), or finished yesterday-or-earlier with at least
        // three entries logged live reaching 70% of the day's need. Everything else is unknown.
        let states = Dictionary(state.dayStatus.map { ($0.day, $0.state) }, uniquingKeysWith: { a, _ in a })
        let entriesByDay = Dictionary(grouping: state.entries, by: \.day)
        var complete: [Day: Double] = [:]
        for day in Set(intakeByDay.keys).union(states.keys) where day < today {
            let kcal = intakeByDay[day]?.kcal ?? 0
            switch states[day] {
            case .complete?: if kcal > 0 { complete[day] = kcal }
            case .fasting?: if kcal == 0 { complete[day] = 0 }
            case .partial?, .inProgress?: break
            case nil:
                let live = (entriesByDay[day] ?? []).filter { $0.updatedAt <= day.adding(days: 1).date().addingTimeInterval(4 * 3600) }
                if live.count >= 3, kcal >= formula * 0.7 { complete[day] = kcal }
            }
        }
        let maintenance = Energy.estimate(trend: trend, usable: complete.filter { !ignored.contains($0.key) }, formula: formula,
                                          through: today.adding(days: -1))

        // Assessment.
        var assessment: AssessmentProgress?
        if let start = state.settings.assessmentStart {
            let before = state.weighIns.filter { $0.day < start && $0.day >= start.adding(days: -21) }.map(\.day)
            let total = assessmentDays(weighInsBeforeStart: Set(before).count)
            let elapsed = start.days(until: today) + 1
            if state.plan == nil {
                var learned: [String] = []
                let logged = complete.keys.filter { $0 >= start }.count
                learned.append(logged == 0 ? "Log what you eat today; nothing needs to change yet." : "\(logged) full day\(logged == 1 ? "" : "s") logged so far.")
                let weighed = Set(state.weighIns.filter { $0.day >= start }.map(\.day)).count
                if elapsed <= 7 {
                    learned.append("Week 1 weight is mostly water, so it isn't used for the estimate yet.")
                } else {
                    learned.append("\(maintenance.label): maintenance about \(Int(maintenance.kcal)) kcal (\(Int(maintenance.low))–\(Int(maintenance.high))).")
                }
                if weighed < max(3, elapsed / 2) { learned.append("Daily weigh-ins sharpen this fastest: first thing, after the bathroom.") }
                if let change = trend.weeklyChange(), elapsed > 10 {
                    let unit = state.profile.units.weight
                    let value = unit.fromKilograms(change)
                    learned.append("Trend: \(value >= 0 ? "+" : "−")\(abs(value).formatted(.number.precision(.fractionLength(2)))) \(unit.symbol) a week while eating as usual.")
                }
                let protein = complete.keys.filter { $0 >= start }.compactMap { intakeByDay[$0]?.protein }.mean
                if let protein { learned.append("Protein has averaged \(Int(protein)) g a day.") }
                assessment = AssessmentProgress(day: min(elapsed, total), totalDays: total, learned: learned, complete: elapsed > total)
            }
        }

        // Planner input, from this app and Lift Track.
        let liftMeasurements = state.lift?.measurements
        let input = PlannerInput(profile: state.profile, history: state.settings.dietHistory, today: today, weightKg: weight,
                                 weeklyChange: trend.weeklyChange(days: 21), maintenance: maintenance, waistCm: liftMeasurements?.waistCm,
                                 bodyFatPercent: liftMeasurements?.bodyFatPercent, strengthScore: state.lift?.strength?.overall,
                                 strengthTrend: state.lift?.stats.first { $0.stat == .strength }?.trend)

        let life = LifeModes.effects(on: today, periods: state.lifeModes)
        let assessing = state.plan == nil
        let deload = state.calendar?.isDeload(today) ?? false
        let checkIn = state.checkIns.last { $0.day <= today }
        let referenceKg = Targets.referenceWeight(kg: weight, heightCm: state.profile.heightCm, waistToHeight: input.waistToHeight)
        var dueCheckIn: CheckIn?
        if !assessing, CheckIns.isDue(last: checkIn, today: today) {
            dueCheckIn = CheckIns.review(previous: checkIn, trend: trend, usable: complete.filter { !ignored.contains($0.key) }, today: today,
                                         phase: state.plan?.phase(on: today), weightKg: weight, referenceKg: referenceKg,
                                         fallbackExpenditure: maintenance.kcal)
        }
        let targets = Targets.today(day: today, assessing: assessing, plan: state.plan, override: state.settings.phaseOverride,
                                    maintenance: maintenance, checkIn: dueCheckIn ?? checkIn, weightKg: weight,
                                    heightCm: state.profile.heightCm, waistToHeight: input.waistToHeight, life: life, deload: deload)

        // Discipline: target adherence on logged days. Not logging is unknown, never a miss.
        let window = Discipline.window(ending: today.adding(days: -1))
        let start = state.settings.assessmentStart ?? window.start
        var items: [AdherenceItem] = []
        var expected = 0, loggedDays = 0
        for day in window.days where day >= start {
            let effects = LifeModes.effects(on: day, periods: state.lifeModes)
            if effects.disciplineExempt { continue }
            expected += 1
            guard complete[day] != nil, let n = intakeByDay[day] ?? (complete[day] == 0 ? .zero : nil) else {
                items.append(AdherenceItem(day: day, kind: .mealLog, label: "Targets", done: nil))
                continue
            }
            loggedDays += 1
            let dayTargets = Targets.today(day: day, assessing: assessing || day < (state.plan?.created).map { Day($0) } ?? day,
                                           plan: state.plan, override: state.settings.phaseOverride, maintenance: maintenance,
                                           checkIn: state.checkIns.last { $0.day <= day }, weightKg: weight, heightCm: state.profile.heightCm,
                                           waistToHeight: input.waistToHeight, life: effects,
                                           deload: state.calendar?.isDeload(day) ?? false)
            let hit = dayTargets.hits(n)
            let done: Bool? = switch (hit.protein, hit.calories) {
            case (nil, nil): true
            case (let p?, nil): p
            case (nil, let c?): c
            case (let p?, let c?): p && c
            }
            items.append(AdherenceItem(day: day, kind: .mealLog, label: "Targets", done: done))
        }
        let discipline = Discipline.score(items, exempt: [], window: window)
        let loggingRate = expected == 0 ? nil : Double(loggedDays) / Double(expected)

        var analysis = MacroAnalysis(trend: trend, weeklyChange: trend.weeklyChange(), maintenance: maintenance, assessment: assessment,
                                     plan: state.plan, phase: state.plan?.phase(on: today), targets: targets,
                                     todayIntake: intakeByDay[today] ?? .zero, intakeByDay: intakeByDay, discipline: discipline,
                                     loggingRate: loggingRate, actions: [], life: life, plannerInput: input, usable: complete,
                                     checkIn: checkIn, dueCheckIn: dueCheckIn, referenceKg: referenceKg)
        analysis.micros = MicroAnalyst.report(entries: state.entries, supplements: state.supplementLogs, complete: Set(complete.keys),
                                              profile: state.profile, kcal: targets.kcal ?? maintenance.kcal, today: today)
        analysis.caffeine = Caffeine.report(day: today, entries: state.entries, supplements: state.supplementLogs,
                                            bedtime: state.bedtime(on: today), limit: state.settings.caffeineLimit ?? Caffeine.defaultLimit,
                                            cutBack: state.settings.caffeineCutBack, complete: Set(complete.keys))
        analysis.hydration = Hydration.day(today, water: state.water, entries: state.entries,
                                           target: state.settings.waterTarget ?? Hydration.target(sex: state.profile.sex))
        analysis.quality = QualityAnalyst.report(entries: state.entries, complete: Set(complete.keys), today: today)
        analysis.actions = actions(state, analysis)
        return analysis
    }

    // MARK: Actions

    static func actions(_ state: MacroState, _ a: MacroAnalysis) -> [MacroAction] {
        var list: [MacroAction] = []
        let today = state.today
        let weighedToday = state.weighIns.contains { $0.day == today }
        let expectingLogs = a.targets.mode != .vacation && a.targets.mode != .illness

        if !weighedToday, expectingLogs {
            list.append(MacroAction(id: "weigh-\(today.iso)", kind: .weighIn, title: "Weigh in",
                                    detail: "Daily weigh-ins are what turn your logging into a maintenance estimate.",
                                    action: "First thing, after the bathroom, before eating.", priority: a.assessment != nil ? 6 : 3))
        }
        if let assessment = a.assessment, assessment.complete {
            list.append(MacroAction(id: "plan-ready", kind: .planReady, title: "Your plan is ready",
                                    detail: "The assessment is done. Maintenance looks like about \(Int(a.maintenance.kcal)) kcal (\(Int(a.maintenance.low))–\(Int(a.maintenance.high))).",
                                    action: "See the recommendation and start it.", priority: 9))
        }
        // Protein short late in the day.
        let hour = Calendar.current.component(.hour, from: Date())
        if let target = a.targets.protein, a.todayIntake.kcal > 0, hour >= 15 {
            let gap = target - a.todayIntake.protein
            if gap >= 25 {
                list.append(MacroAction(id: "protein-\(today.iso)", kind: .protein, title: "\(Int(gap)) g protein to go",
                                        detail: "Protein is what protects muscle\(a.phase?.kind.energy == .deficit ? " in a cut" : "").",
                                        action: gap >= 45 ? "A protein-heavy dinner plus a shake closes it." : "A shake or Greek yogurt closes it.",
                                        priority: 5))
            }
        }
        let yesterday = today.adding(days: -1)
        if expectingLogs, a.intakeByDay[yesterday] == nil, !LifeModes.effects(on: yesterday, periods: state.lifeModes).disciplineExempt,
           !state.entries.isEmpty {
            list.append(MacroAction(id: "yesterday-\(yesterday.iso)", kind: .logYesterday, title: "Yesterday is empty",
                                    detail: "An unlogged day is unknown, not a miss, but the estimate learns from every full day.",
                                    action: "Copy a typical day, or log what you remember.", priority: 4))
        }
        if a.targets.mode == .dietBreak, let change = a.weeklyChange, change >= -0.05 {
            list.append(MacroAction(id: "whoosh", kind: .whoosh, title: "The scale stalled: expected",
                                    detail: "Water held during a cut often drops during a diet break.",
                                    action: "Hold the targets; nothing tightens mid-cut because of the scale.", priority: 2))
        }
        if let plan = a.plan, let boundary = state.calendar?.currentBlock?.end, boundary.days(until: today) == 0 || today.days(until: boundary) == 0,
           PhasePlanner.review(plan, input: a.plannerInput) != nil {
            list.append(MacroAction(id: "review-\(today.iso)", kind: .reviewPlan, title: "Plan check",
                                    detail: "The training block ends today, so the plan was checked against the data.",
                                    action: "Review the suggested change.", priority: 7))
        }
        return list.sorted { $0.priority > $1.priority }
    }

    // MARK: Publishing

    /// What Lift Track and the hub read: the phase, maintenance, and day-by-day logging and targets.
    public static func nutritionSummary(_ state: MacroState, _ a: MacroAnalysis) -> NutritionSummary {
        let phase = a.phase.map { NutritionPhase(kind: $0.kind, ratePerWeek: $0.ratePerWeek, plannedWeeks: $0.weeks, start: $0.start, source: .macroTrack) }
        var days: [NutritionDay] = []
        for day in stride(from: state.today.adding(days: -27), through: state.today, by: 1) {
            guard let n = a.intakeByDay[day] else {
                days.append(NutritionDay(day: day, logged: false, proteinHit: nil, caloriesHit: nil))
                continue
            }
            let hit = a.targets.hits(n)
            days.append(NutritionDay(day: day, logged: true, proteinHit: hit.protein, caloriesHit: hit.calories))
        }
        return NutritionSummary(phase: phase, maintenanceKcal: a.assessment == nil || a.maintenance.basis != .formula ? a.maintenance.kcal : nil,
                                days: days)
    }

    public static func appSummary(_ state: MacroState, _ a: MacroAnalysis) -> AppSummary {
        var stats: [StatReading] = []
        if let rate = a.discipline.rate {
            stats.append(StatReading(stat: .discipline, score: (a.discipline.credit ?? 0) * 100,
                                     label: "Nutrition \(Int((rate * 100).rounded()))%", trend: .notEnoughData, updated: state.today.date()))
        }
        if let logged = a.loggingRate {
            stats.append(StatReading(stat: .vitality, score: logged * 100, label: "Logged \(Int((logged * 100).rounded()))% of days",
                                     trend: .notEnoughData, updated: state.today.date()))
        }
        let sessions: [SessionSummary] = a.intakeByDay.filter { $0.key > state.today.adding(days: -28) }.sorted { $0.key < $1.key }.map { day, n in
            SessionSummary(id: UUID(dayNamespace, salt: day.ordinal), app: .macroTrack, kind: .nutrition,
                           start: day.date(), minutes: 0,
                           metrics: ["kcal": n.kcal, "protein": n.protein, "carbs": n.carbs, "fat": n.fat], planned: true)
        }
        var measurements: BodyMeasurements?
        if let latest = a.trend.latest { measurements = BodyMeasurements(day: latest.day, weightKg: (latest.trend * 10).rounded() / 10) }
        return AppSummary(app: .macroTrack, stats: stats, sessions: sessions, discipline: a.discipline, measurements: measurements,
                          phaseUsed: a.phase.map { NutritionPhase(kind: $0.kind, ratePerWeek: $0.ratePerWeek, source: .macroTrack) })
    }
}

/// Stable ids for per-day summaries, so republishing doesn't churn them.
let dayNamespace = UUID(uuidString: "6D41C2A0-1F1E-4C3B-9E5A-8A7D2C9B0F11")!

extension UUID {
    /// A stable id derived from another and a number.
    init(_ base: UUID, salt: Int) {
        var bytes = base.uuid
        withUnsafeMutableBytes(of: &bytes) { raw in
            var s = UInt64(bitPattern: Int64(salt)).littleEndian
            withUnsafeBytes(of: &s) { saltBytes in
                for i in 0..<8 { raw[8 + i] ^= saltBytes[i] }
            }
        }
        self.init(uuid: bytes)
    }
}
