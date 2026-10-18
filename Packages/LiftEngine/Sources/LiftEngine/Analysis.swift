import Foundation
import ExerciseLibrary
import SystemCore

/// Everything Lift Track knows, as plain values.
public struct LiftState: Sendable {
    public var profile: SharedProfile
    public var settings: LiftSettings
    public var gym: Gym
    public var catalog: ExerciseCatalog
    public var sessions: [SessionRecord]
    public var activities: [ActivityLog]
    public var measurements: [BodyMeasurements]
    public var mobility: [MobilityResult]
    public var benchmarks: [BenchmarkResult]
    public var mesocycles: [Mesocycle]
    public var lifeModes: [LifeModePeriod]
    public var recovery: [RecoveryDay]
    /// Daily steps from Health, today's so far included.
    public var steps: [StepDay]
    public var bodyweightKg: Double?
    /// A body-fat sample from Health in the last two weeks.
    public var bodyFatPercent: Double?
    public var vo2Max: Double?
    public var restingHeartRate: Double?
    /// Macro Track's summary, when it's installed.
    public var nutrition: NutritionSummary?
    public var recommendations: [Recommendation]
    public var today: Day

    public init(profile: SharedProfile, settings: LiftSettings, gym: Gym, catalog: ExerciseCatalog, sessions: [SessionRecord] = [],
                activities: [ActivityLog] = [], measurements: [BodyMeasurements] = [], mobility: [MobilityResult] = [],
                benchmarks: [BenchmarkResult] = [], mesocycles: [Mesocycle] = [], lifeModes: [LifeModePeriod] = [],
                recovery: [RecoveryDay] = [], steps: [StepDay] = [], bodyweightKg: Double? = nil, bodyFatPercent: Double? = nil, vo2Max: Double? = nil,
                restingHeartRate: Double? = nil, nutrition: NutritionSummary? = nil, recommendations: [Recommendation] = [],
                today: Day = .today) {
        self.profile = profile
        self.settings = settings
        self.gym = gym
        self.catalog = catalog
        self.sessions = sessions
        self.activities = activities
        self.measurements = measurements
        self.mobility = mobility
        self.benchmarks = benchmarks
        self.mesocycles = mesocycles
        self.lifeModes = lifeModes
        self.recovery = recovery
        self.steps = steps
        self.bodyweightKg = bodyweightKg
        self.bodyFatPercent = bodyFatPercent
        self.vo2Max = vo2Max
        self.restingHeartRate = restingHeartRate
        self.nutrition = nutrition
        self.recommendations = recommendations
        self.today = today
    }

    /// Body weight for standards and bodyweight exercises: Health, then the tape, then a guess.
    public var effectiveBodyweight: Double {
        bodyweightKg ?? measurements.sorted { $0.day < $1.day }.last(where: { $0.weightKg != nil })?.weightKg
            ?? (profile.sex == .female ? 65 : 80)
    }

    public var phase: NutritionPhase { PhaseResolver.current(published: nutrition?.phase, selfReported: settings.selfReportedPhase) }

    /// When the current phase began, for the step aim's usual count: Macro Track's phase start, else
    /// when the phase answer last changed, else when training here began.
    public var phaseStart: Day? {
        if let published = nutrition?.phase {
            if let start = published.start { return start }
        } else if settings.selfReportedPhase != nil, let since = settings.selfReportedPhaseSince {
            return since
        }
        return settings.assessmentStart ?? settings.onboardedAt.map { Day($0) }
    }

    /// The first day of steps the analysis needs: four weeks before the phase began (within a
    /// year), and at least the last eight weeks.
    public var stepsNeededSince: Day {
        let recent = today.adding(days: -56)
        guard let start = phaseStart else { return recent }
        return max(today.adding(days: -365), min(recent, start.adding(days: -28)))
    }

    /// Days of illness: their steps say nothing about habits.
    var illnessDays: Set<Day> {
        var days = Set<Day>()
        for period in lifeModes {
            if case .illness = period.kind { days.formUnion(period.range(openUntil: today).days) }
        }
        return days
    }
}

/// A prescriptive insight: every one ends in a concrete action, or it isn't shown.
public struct NextAction: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case stall, deloadEarly, checkIn, measure, mobility, conditioning, smallerPlan, physio, generate }

    public var id: String
    public var kind: Kind
    public var stat: StatKind
    public var title: String
    /// What was seen, in neutral words.
    public var detail: String
    /// The thing to do.
    public var action: String
    public var priority: Double
}

/// Today's slot in the program.
public struct NextSession: Hashable, Sendable {
    public var mesocycle: Mesocycle
    public var day: PlannedDay
    public var dayIndex: Int
    /// Whether today is one of the person's training days with sessions still to do this week.
    public var scheduledToday: Bool
    public var doneThisWeek: Int
    public var plannedThisWeek: Int
    /// The next training weekday, when today isn't one.
    public var nextDay: Day?
}

public struct LiftAnalysis: Sendable {
    public var trust: TrustState
    public var history: [String: [LoggedSet]]
    public var strength: StrengthProfile
    public var stalls: [StallReport]
    public var fatigue: FatigueAssessment
    public var discipline: DisciplineScore
    public var physique: PhysiqueAnalysis
    public var agility: AgilityAnalysis
    public var endurance: EnduranceAnalysis
    public var phase: NutritionPhase
    public var life: LifeModeEffects
    public var mesocycle: Mesocycle?
    /// The current block after vacations and any early deload.
    public var block: TrainingBlock?
    public var next: NextSession?
    public var assessment: AssessmentStatus?
    public var actions: [NextAction]
    public var quests: [Quest]
    public var calendar: SystemCalendar
    public var adherence: [AdherenceItem]
    /// Every sauna and steam session, oldest first.
    public var heat: [HeatLog] = []
    /// The daily step aim, when Health has enough steps to know the usual count.
    public var steps: StepAim?
}

public enum Analyst {
    public static func analyse(_ state: LiftState) -> LiftAnalysis {
        let today = state.today
        let sessions = state.sessions.sorted { $0.start < $1.start }
        var history: [String: [LoggedSet]] = [:]
        for session in sessions {
            for log in session.exercises { history[log.exerciseID, default: []].append(contentsOf: log.sets) }
        }

        // Trust is rebuilt from the evidence every time, so every device agrees.
        var trust = TrustState(experience: state.profile.experience)
        for session in sessions {
            for log in session.exercises {
                trust.record(Calibration.observations(sets: log.sets, exercise: state.catalog.resolve(log.exerciseID)))
            }
        }

        let bodyweight = state.effectiveBodyweight
        var traits: [String: any ExerciseTraits] = [:]
        for id in history.keys { traits[id] = state.catalog.resolve(id) }
        let strength = StrengthEstimator.profile(history: history, exercises: traits, trust: trust, bodyweightKg: bodyweight,
                                                 sex: state.profile.sex, today: today)

        // Fatigue: lifting, conditioning and everything outside, with feedback and recovery.
        var events: [FatigueEvent] = sessions.map { session in
            var load = FatigueLoad.zero
            for set in session.sets { load = load + FatigueBudget.cost(of: set, exercise: state.catalog.resolve(set.exerciseID)) }
            for c in session.conditioning { load = load + FatigueBudget.conditioningCost(minutes: c.minutes, zone: c.zone) }
            return FatigueEvent(day: session.day, load: load, feedback: session.feedback)
        }
        events += state.activities.map { FatigueEvent(day: $0.day, load: $0.fatigue) }
        // Steps: an aim from the usual count and the phase; long unlogged days on foot spend the budget.
        let stepAim = state.phaseStart.flatMap { anchor in
            Steps.aim(days: state.steps, anchor: anchor, energy: state.phase.kind.energy, age: state.profile.age(on: today), today: today,
                      exempt: state.illnessDays)
        }
        if let stepAim {
            let logged = Set(state.activities.map(\.day))
            let walking = ActivityType.walking.hourlyFatigue
            events += Steps.longDays(state.steps.filter { $0.day < today }, baseline: stepAim.baseline, skipping: logged).map { long in
                let hours = Double(long.minutes) / 60
                return FatigueEvent(day: long.day, load: FatigueLoad(systemic: walking.systemic * hours,
                                                                     local: walking.local.mapValues { $0 * hours }))
            }
        }
        let lifeStress = LifeModes.lifeStress(in: DayRange(today.adding(days: -27), today), periods: state.lifeModes)
        let series = history.map { id, sets in StrengthEstimator.sessionBests(sets, basis: state.catalog.resolve(id).loadBasis, trust: trust) }
        let trend = FatigueBudget.performanceTrend(series, today: today)
        let fatigue = FatigueBudget.assess(events: events, recovery: state.recovery, lifeStress: lifeStress, performanceTrend: trend, today: today)

        let phase = state.phase
        let life = LifeModes.effects(on: today, periods: state.lifeModes)

        // The current mesocycle, reshaped around vacations.
        let vacations = state.lifeModes.compactMap { period -> DayRange? in
            if case .vacation = period.kind { return period.range(openUntil: today) }
            return nil
        }
        let mesocycle = state.mesocycles.sorted { $0.block.start < $1.block.start }.last
        var block = mesocycle.map { BlockScheduler.reflow($0.block, vacations: vacations) }

        // Stalls, read by phase and fatigue.
        var stalls: [StallReport] = []
        if let mesocycle {
            for slot in mesocycle.days.flatMap(\.strengthSlots) where !stalls.contains(where: { $0.exerciseID == slot.exerciseID }) {
                let exercise = state.catalog.resolve(slot.exerciseID)
                let context = ProgressionContext(exercise: exercise, increments: state.gym.increments(for: exercise.equipment), trust: trust,
                                                 phase: phase.effects, bodyweightKg: bodyweight, history: history[exercise.id] ?? [])
                if let stall = Stalls.detect(context, sets: slot.sets(week: 0), repRange: slot.repRange, today: today, phase: phase.effects,
                                             beatUp: fatigue.action != .none) {
                    stalls.append(stall)
                }
            }
        }

        let physique = Physique.analyse(state.measurements, sex: state.profile.sex, heightCm: state.profile.heightCm, weightKg: state.bodyweightKg,
                                        measuredBodyFat: state.bodyFatPercent, targets: state.settings.proportionTargets)
        let agility = Agility.analyse(state.mobility)
        let conditioningMinutes = Double(sessions.filter { $0.day > today.adding(days: -28) }.flatMap(\.conditioning).map(\.minutes).reduce(0, +))
            + Double(state.activities.filter { $0.day > today.adding(days: -28) && ($0.type.statCredit[.endurance] ?? 0) > 0 }.map(\.minutes).reduce(0, +))
        let hrrPoints = sessions.flatMap(\.sets).compactMap { set in set.heartRateDrop60.map { (day: Day(set.date), drop: $0) } }
        let endurance = Endurance.analyse(vo2Max: state.vo2Max, restingHeartRate: state.restingHeartRate, benchmarks: state.benchmarks,
                                          hrrTrend: HeartRateRecovery.trend(hrrPoints), weeklyConditioningMinutes: conditioningMinutes / 4,
                                          sex: state.profile.sex, age: state.profile.age(on: today))

        // Discipline: the plan, not perfection.
        let adherence = adherenceItems(state, sessions: sessions, block: block, today: today)
        let window = Discipline.window(ending: today)
        let discipline = Discipline.score(adherence, exempt: LifeModes.exemptDays(in: window, periods: state.lifeModes), window: window)

        var next: NextSession?
        if let mesocycle, !mesocycle.days.isEmpty {
            next = nextSession(mesocycle, sessions: sessions, profile: state.profile, today: today)
        }
        var assessment: AssessmentStatus?
        if let mesocycle, mesocycle.block.kind == .assessment {
            assessment = Assessment.status(mesocycle, sessions: sessions, trust: trust, strength: strength, catalog: state.catalog, today: today)
        }

        // An early deload, when the budget says so.
        if let current = block, let moved = BlockScheduler.deloadEarly(current, today: today, fatigue: fatigue) { block = moved }

        let calendar = BlockScheduler.calendar(blocks: block.map { [$0] } ?? [], today: today)
        var analysis = LiftAnalysis(trust: trust, history: history, strength: strength, stalls: stalls, fatigue: fatigue, discipline: discipline,
                                    physique: physique, agility: agility, endurance: endurance, phase: phase, life: life, mesocycle: mesocycle,
                                    block: block, next: next, assessment: assessment, actions: [], quests: [], calendar: calendar,
                                    adherence: adherence)
        analysis.heat = sessions.flatMap { $0.heat ?? [] }.sorted { $0.date < $1.date }
        analysis.steps = stepAim
        analysis.actions = actions(state, analysis)
        analysis.quests = quests(state, analysis)
        return analysis
    }

    // MARK: Schedule

    /// The next day of the program in rotation: missed days don't skip ahead, they wait.
    public static func nextSession(_ mesocycle: Mesocycle, sessions: [SessionRecord], profile: SharedProfile, today: Day) -> NextSession {
        let done = sessions.filter { $0.mesocycleID == mesocycle.id && $0.planned }
        let index = done.count % mesocycle.days.count
        let weekStart = today.startOfWeek
        let doneThisWeek = done.filter { $0.day >= weekStart && $0.day <= today }.count
        let trainingDays = profile.schedule.trainingDays
        let doneToday = done.contains { $0.day == today }
        let scheduledToday = trainingDays.contains(today.weekday) && doneThisWeek < profile.schedule.daysPerWeek && !doneToday
        var nextDay: Day?
        if !scheduledToday {
            nextDay = (1...7).map { today.adding(days: $0) }.first { trainingDays.contains($0.weekday) }
        }
        return NextSession(mesocycle: mesocycle, day: mesocycle.days[index], dayIndex: index, scheduledToday: scheduledToday,
                           doneThisWeek: doneThisWeek, plannedThisWeek: profile.schedule.daysPerWeek, nextDay: nextDay)
    }

    /// Planned sessions and declared classes, day by day. A missed session dents the average;
    /// extra sessions beyond the plan earn nothing.
    static func adherenceItems(_ state: LiftState, sessions: [SessionRecord], block: TrainingBlock?, today: Day) -> [AdherenceItem] {
        guard let start = state.settings.assessmentStart ?? state.mesocycles.map(\.block.start).min() else { return [] }
        let window = Discipline.window(ending: today)
        let first = max(start, window.start)
        guard first <= today else { return [] }
        var items: [AdherenceItem] = []
        let schedule = state.profile.schedule
        var week = first.startOfWeek
        while week <= today {
            let weekDays = (0..<7).map { week.adding(days: $0) }
            let trainingDays = weekDays.filter { day in
                day >= first && day <= today && schedule.trainingDays.contains(day.weekday)
                    && LifeModes.effects(on: day, periods: state.lifeModes).trainingExpected
            }
            let done = sessions.filter { $0.planned && $0.day >= week && $0.day <= week.adding(days: 6) && $0.day <= today }.count
            for (i, day) in trainingDays.prefix(schedule.daysPerWeek).enumerated() {
                // Today's session isn't missed yet.
                if day == today, done <= i { continue }
                items.append(AdherenceItem(day: day, kind: .session, label: "Planned session", done: done > i))
            }
            week = week.adding(days: 7)
        }
        for recurring in state.profile.recurring {
            for day in DayRange(first, today.adding(days: -1)).days where recurring.weekdays.contains(day.weekday) {
                guard LifeModes.effects(on: day, periods: state.lifeModes).trainingExpected else { continue }
                let attended = state.activities.contains { $0.type == recurring.activity && abs($0.day.days(until: day)) <= 1 }
                // Unlogged classes are unknown, not missed.
                items.append(AdherenceItem(day: day, kind: .declaredClass, label: recurring.activity.label, done: attended ? true : nil))
            }
        }
        return items
    }

    // MARK: Actions

    static func actions(_ state: LiftState, _ a: LiftAnalysis) -> [NextAction] {
        var list: [NextAction] = []
        let today = state.today
        let unit = state.profile.units.weight

        for stall in a.stalls where stall.reading != .expectedInDeficit {
            let exercise = state.catalog.resolve(stall.exerciseID)
            var detail = "\(exercise.name) hasn't set a new best in \(stall.weeks) weeks."
            if let nutrition = state.nutrition {
                let (hit, known) = nutrition.proteinHits(in: DayRange(today.adding(days: -6), today))
                if known >= 4, hit < known - 2 { detail += " Protein was under target \(known - hit) of the last \(known) logged days." }
            }
            let action: String
            if stall.reading == .recovery {
                detail += " You've also been feeling beat up."
                action = "Recovery first: the next block swaps the costliest lifts before cutting any work."
            } else if let s = stall.suggestion, let load = s.loadKg {
                let value = unit.fromKilograms(load)
                action = "Next session, \(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit.symbol) for \(stall.suggestedSets)×\(s.targetReps)."
            } else {
                action = "Next session, add the smallest step and drop to the bottom of the rep range."
            }
            list.append(NextAction(id: "stall-\(stall.exerciseID)", kind: .stall, stat: .strength, title: "\(exercise.name) has stalled",
                                   detail: detail, action: action, priority: 5 + Double(stall.weeks) * 0.2))
        }

        if a.fatigue.action == .deloadEarly, let block = a.block, case .loading = block.week(of: today) {
            list.append(NextAction(id: "deload-early", kind: .deloadEarly, stat: .vitality, title: "Deload now",
                                   detail: a.fatigue.signals.prefix(3).joined(separator: " "),
                                   action: "Take this week as the deload: lighter and shorter, then a fresh block.", priority: 9))
        }

        if let block = a.block, let checkIn = block.checkInDay, block.week(of: today) == .deload {
            let days = today.days(until: checkIn)
            list.append(NextAction(id: "check-in-\(checkIn.iso)", kind: .checkIn, stat: .agility, title: "Check-in \(days <= 0 ? "today" : "this week")",
                                   detail: "Plain check-ins land at the end of the deload, when you're fresh.",
                                   action: "Mobility tests, a \(state.settings.benchmark.label) and measurements.", priority: 7))
        } else if a.mesocycle?.block.kind == .assessment, state.mobility.isEmpty, let start = a.mesocycle?.block.start,
                  start.days(until: today) >= 3 {
            list.append(NextAction(id: "baseline-tests", kind: .checkIn, stat: .agility, title: "Baseline tests",
                                   detail: "Five quick mobility tests set the starting point and choose your limiter.",
                                   action: "Take the mobility tests after your next session (about 10 minutes).", priority: 6))
        }

        let lastMeasured = state.measurements.map(\.day).max()
        if a.mesocycle != nil, lastMeasured.map({ $0.days(until: today) > 35 }) ?? true {
            list.append(NextAction(id: "measure", kind: .measure, stat: .physique, title: "Measurements due",
                                   detail: lastMeasured == nil ? "No tape measurements yet." : "It's been over five weeks.",
                                   action: "Shoulders, waist, arms and thighs: two minutes with a tape.", priority: 3))
        }

        if !a.agility.seePhysio.isEmpty {
            list.append(NextAction(id: "physio", kind: .physio, stat: .agility, title: "See a physio",
                                   detail: "\(a.agility.seePhysio.map(\.label).joined(separator: ", ")) hurt or got worse.",
                                   action: "Pain or worsening symptoms need a physio, not more stretching.", priority: 8))
        }

        if let band = a.discipline.band, band == .below, (a.discipline.rate ?? 1) < 0.7 {
            list.append(NextAction(id: "smaller-plan", kind: .smallerPlan, stat: .discipline, title: "Make it easier to win",
                                   detail: "You've done \(a.discipline.completed) of \(a.discipline.planned) planned sessions in four weeks.",
                                   action: "Try \(max(2, state.profile.schedule.daysPerWeek - 1)) shorter sessions this week. Showing up is the target, not volume.",
                                   priority: 6))
        }

        if a.endurance.engineLagging, !state.settings.includeConditioning {
            list.append(NextAction(id: "zone2", kind: .conditioning, stat: .endurance, title: "Build the engine",
                                   detail: "Under an hour of easy cardio a week.",
                                   action: "Add 20 minutes of Zone 2 on a free evening this week.", priority: 2))
        }
        return list.sorted { $0.priority > $1.priority }
    }

    static func quests(_ state: LiftState, _ a: LiftAnalysis) -> [Quest] {
        var list: [Quest] = []
        let today = state.today
        if let next = a.next, next.scheduledToday {
            for overflow in next.day.overflow {
                list.append(Quest(id: "lift-\(today.iso)-\(overflow.kind.rawValue)", title: "\(overflow.title) this evening",
                                  detail: "It didn't fit in today's session.", stat: overflow.stat, source: .liftTrack, minutes: overflow.minutes,
                                  day: today, timeOfDay: .evening, priority: overflow.stat == .agility ? 2 : 1))
            }
        }
        if let limiter = a.agility.limiter, !list.contains(where: { $0.stat == .agility }), next(a)?.scheduledToday != true {
            list.append(Quest(id: "lift-\(today.iso)-mobility", title: "10 min \(limiter.label.lowercased()) mobility",
                              detail: "Your weakest mobility test.", stat: .agility, source: .liftTrack, minutes: 10, day: today,
                              timeOfDay: .evening, priority: 1.5))
        }
        if let walk = walkQuest(state, a) { list.append(walk) }
        return Quests.forDay(today, from: list)
    }

    private static func next(_ a: LiftAnalysis) -> NextSession? { a.next }

    /// A walk on a rest day when the week's steps are behind the aim: the gap to the aim as minutes
    /// of brisk walking. Not on lift or class days, while ill, or with a hip, knee or ankle injury,
    /// and gone once today reaches the aim.
    static func walkQuest(_ state: LiftState, _ a: LiftAnalysis) -> Quest? {
        let today = state.today
        guard let steps = a.steps, steps.actionable, steps.onTrack == false, let recent = steps.recent, (steps.today ?? 0) < steps.aim,
              next(a)?.scheduledToday != true, !state.sessions.contains(where: { $0.day == today }),
              !state.profile.recurring.contains(where: { $0.weekdays.contains(today.weekday) }),
              !state.illnessDays.contains(today),
              !a.life.injuries.contains(where: { $0.parts.contains { [.hip, .knee, .ankle].contains($0.joint) } }) else { return nil }
        let minutes = clamp(Int((Double(steps.gap) / Double(Steps.perMinute) / 5).rounded()) * 5, 10, 40)
        return Quest(id: "lift-\(today.iso)-walk", title: "\(minutes)-minute walk",
                     detail: "Steps have averaged \(Steps.round(recent, to: 100).formatted()) a day over the last week; the aim is \(steps.aim.formatted()).",
                     stat: .vitality, source: .liftTrack, minutes: minutes, day: today, timeOfDay: .evening,
                     priority: steps.energy == .deficit ? 1.8 : 1.2)
    }

    // MARK: Publishing

    /// The small summary published to the shared container for the hub and the other apps.
    public static func summary(_ state: LiftState, _ a: LiftAnalysis) -> AppSummary {
        let today = state.today
        var stats: [StatReading] = []
        if let overall = a.strength.overall {
            stats.append(StatReading(stat: .strength, score: overall, label: StrengthStandards.level(for: overall), trend: strengthTrend(a)))
        }
        if let score = a.physique.score { stats.append(StatReading(stat: .physique, score: score, label: "Proportions", trend: .notEnoughData)) }
        if let score = a.endurance.score {
            let trend: Trajectory = a.endurance.benchmarkChange.map { $0 > 0.005 ? .onPace : ($0 < -0.01 ? .regressing : .stalled) } ?? .notEnoughData
            stats.append(StatReading(stat: .endurance, score: score, label: "Engine", trend: trend))
        }
        if let score = a.agility.score { stats.append(StatReading(stat: .agility, score: score, label: a.agility.limiter.map { "Limiter: \($0.label)" } ?? "Mobile", trend: .notEnoughData)) }
        if let rate = a.discipline.rate {
            stats.append(StatReading(stat: .discipline, score: (a.discipline.credit ?? 0) * 100, label: "Training \(Int((rate * 100).rounded()))%", trend: .notEnoughData))
        }
        // Stamped with the day, not the moment, so an unchanged summary compares equal.
        stats = stats.map { reading in
            var reading = reading
            reading.updated = today.date()
            return reading
        }
        let since = today.adding(days: -42)
        let nutritionKnown = state.nutrition?.phase != nil
        var shared: [SessionSummary] = state.sessions.filter { $0.day >= since }.map { session in
            var load = FatigueLoad.zero
            for set in session.sets { load = load + FatigueBudget.cost(of: set, exercise: state.catalog.resolve(set.exerciseID)) }
            let volume = session.workSets.map { $0.loadKg * Double($0.reps) }.reduce(0, +)
            return SessionSummary(id: session.id, app: .liftTrack, kind: .strength, start: session.start, minutes: session.minutes,
                                  metrics: ["sets": Double(session.workSets.count), "volumeKg": volume, "nutritionKnown": nutritionKnown ? 1 : 0],
                                  fatigue: load, statCredit: [.strength: 1], planned: session.planned)
        }
        shared += state.activities.filter { $0.day >= since }.map { log in
            SessionSummary(id: log.id, app: .liftTrack, kind: .activity, activity: log.type, start: log.start, minutes: log.minutes,
                           metrics: ["intensity": Double(log.intensity)], fatigue: log.fatigue, statCredit: log.statCredit, planned: false)
        }
        // Complete days only, so today's climbing count doesn't republish all day.
        let stepDays = state.steps.filter { $0.day >= today.adding(days: -56) && $0.day < today }.sorted { $0.day < $1.day }
        let steps = stepDays.isEmpty ? nil : StepSummary(days: stepDays, aim: a.steps?.aim, baseline: a.steps?.baseline)
        return AppSummary(app: .liftTrack, stats: stats, sessions: shared.sorted { $0.start < $1.start }, quests: a.quests,
                          strength: a.strength.categories.isEmpty ? nil : a.strength, fatigue: a.fatigue.status, discipline: a.discipline,
                          measurements: a.physique.latest, physique: a.physique.latest == nil ? nil : a.physique.direction,
                          mobility: Array(a.agility.latest.values), benchmarks: state.benchmarks.suffix(6),
                          stalls: a.stalls, phaseUsed: a.phase, steps: steps)
    }

    static func strengthTrend(_ a: LiftAnalysis) -> Trajectory {
        let slopes = a.history.compactMap { _, sets -> Double? in
            let bests = StrengthEstimator.sessionBests(sets, basis: .external, trust: a.trust).suffix(8).map(\.e1rm)
            guard bests.count >= 4, let first = bests.first, first > 0 else { return nil }
            return (bests.map { $0 / first }).slope
        }
        guard let mean = slopes.mean else { return .notEnoughData }
        if mean > 0.002 { return .onPace }
        return mean < -0.004 ? .regressing : .stalled
    }
}
