import Foundation
import Testing
import SystemCore
@testable import NutritionEngine

/// A person with a true maintenance who eats, logs and weighs in like people do: noisy days,
/// gaps, partial logs, water swings, and a misread now and then. Deterministic.
struct SimulatedEater {
    var maintenance: Double
    var startKg: Double
    var logging: Double = 0.85
    var noiseKg: Double = 0.6
    var seed: UInt64 = 42
    var start = Day(year: 2026, month: 1, day: 5)

    struct Run {
        var entries: [FoodEntry] = []
        var weighIns: [WeighIn] = []
        var statuses: [DayStatus] = []
        var trueKg: [Day: Double] = [:]
    }

    /// `intake(day index, today's target)` decides what's eaten.
    func run(days: Int, intake: (Int, Day) -> Double, skipWeighIn: Set<Int> = [], misreads: [Int: Double] = [:]) -> Run {
        var rng = SplitMix(seed: seed)
        var run = Run()
        var kg = startKg
        for i in 0..<days {
            let day = start.adding(days: i)
            let eaten = max(800, intake(i, day) + rng.normal() * 250)
            let date = day.date().addingTimeInterval(12 * 3600)
            // Water: an extra kilo held in week one that drops out, plus daily swings.
            let water = i < 7 ? 1.0 - Double(i) / 7 : 0
            if !skipWeighIn.contains(i) {
                let scale = misreads[i] ?? (kg + water + rng.normal() * noiseKg)
                run.weighIns.append(WeighIn(date: day.date().addingTimeInterval(7 * 3600), kg: scale))
            }
            run.trueKg[day] = kg
            let logged = rng.uniform() < logging
            if logged {
                for (n, share) in [0.25, 0.35, 0.3, 0.1].enumerated() {
                    run.entries.append(FoodEntry(date: date.addingTimeInterval(Double(n) * 3600), meal: MealSlot.allCases[n], name: "Food \(n)",
                                                 amountLabel: "1", nutrients: Nutrients(kcal: eaten * share, protein: eaten * share * 0.05,
                                                                                         carbs: eaten * share * 0.11, fat: eaten * share * 0.035),
                                                 source: .search, updatedAt: date))
                }
                run.statuses.append(DayStatus(day: day, state: .complete))
            } else if rng.uniform() < 0.5 {
                // A partial day: some entries, marked partial, so it doesn't teach the estimate.
                run.entries.append(FoodEntry(date: date, meal: .lunch, name: "Partial", amountLabel: "1",
                                             nutrients: Nutrients(kcal: eaten * 0.4, protein: 20, carbs: 40, fat: 15), source: .search, updatedAt: date))
                run.statuses.append(DayStatus(day: day, state: .partial))
            }
            kg += (eaten - maintenance) / Energy.kcalPerKg
        }
        return run
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func normal() -> Double {
        let u1 = max(1e-12, uniform()), u2 = uniform()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

func profile(goals: [OutcomeGoal] = [.biggerAndStronger], experience: TrainingExperience = .intermediate) -> SharedProfile {
    SharedProfile(goals: goals, schedule: TrainingSchedule(daysPerWeek: 4, minutesPerSession: 60), experience: experience, sex: .male,
                  birthYear: 1991, heightCm: 180, units: UnitPreference(weight: .kg, length: .cm), createdBy: .macroTrack)
}

func usable(_ run: SimulatedEater.Run) -> [Day: Double] {
    var totals: [Day: Double] = [:]
    for e in run.entries { totals[e.day, default: 0] += e.nutrients.kcal }
    var result: [Day: Double] = [:]
    for s in run.statuses where s.state == .complete { result[s.day] = totals[s.day] }
    return result
}

@Suite("Simulated eaters")
struct SimulatedEaterTests {
    @Test("Maintenance converges from eating and weighing in, through water and noise",
          arguments: [(2600.0, 2250.0), (2200.0, 2600.0), (3000.0, 2500.0)])
    func maintenanceConverges(truth: Double, eats: Double) {
        let formula = Energy.formula(sex: .male, kg: 84, heightCm: 180, age: 35, trainingDays: 4, otherActiveMinutes: 0)
        var contained = 0
        for seed in [1, 7, 42, 99, 123, 2026] as [UInt64] {
            let eater = SimulatedEater(maintenance: truth, startKg: 84, seed: seed)
            let run = eater.run(days: 28) { _, _ in eats }
            func estimate(through d: Int) -> MaintenanceEstimate {
                let end = eater.start.adding(days: d)
                let trend = Weight.trend(run.weighIns.filter { $0.day <= end }, through: end)
                return Energy.estimate(trend: trend, usable: usable(run).filter { $0.key <= end }, formula: formula, through: end)
            }
            let early = estimate(through: 13), late = estimate(through: 27)
            #expect(early.spread > late.spread, "seed \(seed): \(early.spread) vs \(late.spread)")
            #expect(abs(late.kcal - truth) <= 275, "seed \(seed): \(late.kcal) for \(truth), formula \(formula)")
            #expect(late.basis != .formula)
            if late.low <= truth && late.high >= truth { contained += 1 }
        }
        #expect(contained >= 5, "the range held the truth \(contained) of 6 times")
    }

    @Test("Weekly check-ins move targets gradually toward the truth")
    func checkInsConverge() {
        let eater = SimulatedEater(maintenance: 2400, startKg: 90, logging: 0.9)
        var checkIns: [CheckIn] = [CheckIn(day: eater.start.adding(days: 20), expenditure: 2800, kcal: 2300, protein: 180, carbs: 200,
                                           fat: 70, status: .updated, reason: "Start")]
        let phase = PlannedPhase(kind: .cut, ratePerWeek: -0.005, weeks: 12, start: eater.start.adding(days: 20))
        let run = eater.run(days: 21 + 56) { i, day in
            checkIns.last { $0.day <= day }.map(\.kcal) ?? 2400
        }
        var expenditures: [Double] = []
        for week in 1...8 {
            let day = eater.start.adding(days: 20 + week * 7)
            let trend = Weight.trend(run.weighIns.filter { $0.day < day }, through: day.adding(days: -1))
            let next = CheckIns.review(previous: checkIns.last, trend: trend, usable: usable(run).filter { $0.key < day }, today: day,
                                       phase: phase, weightKg: trend.latest?.trend ?? 90, referenceKg: 90, fallbackExpenditure: 2800)
            #expect(abs(next.kcal - checkIns.last!.kcal) <= 150.01, "week \(week): \(checkIns.last!.kcal) → \(next.kcal)")
            checkIns.append(next)
            expenditures.append(next.expenditure)
        }
        // The overestimate shrinks toward 2400.
        #expect(abs(expenditures.last! - 2400) < abs(2800 - 2400) * 0.5, "\(expenditures)")
    }

    @Test("A lone misread is left out, and a gap never counts as zero")
    func misreadsAndGaps() {
        let eater = SimulatedEater(maintenance: 2500, startKg: 80, noiseKg: 0.3)
        let run = eater.run(days: 21, intake: { _, _ in 2500 }, skipWeighIn: [10, 11], misreads: [15: 86])
        let trend = Weight.trend(run.weighIns, through: eater.start.adding(days: 20))
        #expect(trend.outliers.contains { $0.kg == 86 })
        #expect(abs((trend.latest?.trend ?? 0) - 80) < 1)
        // Partial days are excluded from what the estimate learns from.
        let partial = run.statuses.filter { $0.state == .partial }.map(\.day)
        #expect(partial.allSatisfy { usable(run)[$0] == nil })
    }

    @Test("The trend follows a steady loss without lagging behind the scale")
    func trendKeepsUp() {
        var error = 0.0
        for seed in 1...12 as ClosedRange<UInt64> {
            let eater = SimulatedEater(maintenance: 2600, startKg: 84, noiseKg: 0.6, seed: seed)
            let run = eater.run(days: 42) { _, _ in 2100 }
            let end = eater.start.adding(days: 41)
            let trend = Weight.trend(run.weighIns, through: end)
            error += (trend.latest?.trend ?? 0) - (run.trueKg[end] ?? 0)
        }
        // Losing about 0.45 kg a week: a plain 7-day average would sit ~0.8 kg high.
        #expect(abs(error / 12) < 0.25, "mean error \(error / 12) kg")
    }

    @Test("The first week's water doesn't masquerade as fat loss")
    func waterWeek() {
        let eater = SimulatedEater(maintenance: 2500, startKg: 80, noiseKg: 0.2)
        let run = eater.run(days: 12) { _, _ in 2500 }
        let trend = Weight.trend(run.weighIns, through: eater.start.adding(days: 11))
        let formula = 2500.0
        let estimate = Energy.estimate(trend: trend, usable: usable(run), formula: formula, through: eater.start.adding(days: 11))
        // Eating at maintenance while a kilo of water drops: the estimate must not run away.
        #expect(abs(estimate.kcal - 2500) <= 250, "\(estimate)")
    }
}

@Suite("Phase planning")
struct PhaseTests {
    let today = Day(year: 2026, month: 3, day: 2)

    func input(waist: Double?, goals: [OutcomeGoal], history: DietHistory = .none, maintenance: Double = 2600, formula: Double = 2600,
               experience: TrainingExperience = .intermediate, strength: Double? = nil, trend: Trajectory? = nil, change: Double? = nil) -> PlannerInput {
        PlannerInput(profile: profile(goals: goals, experience: experience), history: history, today: today, weightKg: 82, weeklyChange: change,
                     maintenance: MaintenanceEstimate(kcal: maintenance, low: maintenance - 150, high: maintenance + 150, basis: .data, days: 21,
                                                      formula: formula),
                     waistCm: waist, strengthScore: strength, strengthTrend: trend)
    }

    @Test func higherWaistMeansACut() {
        let plan = PhasePlanner.recommend(input(waist: 104, goals: [.leaner]))
        #expect(plan.phases.first?.kind == .cut)
        #expect(plan.phases.contains { $0.kind == .dietBreak })
        #expect(!plan.headline.lowercased().contains("fat ") || !plan.headline.lowercased().contains("you look"))
    }

    @Test func samsWorkedExample() {
        // Off a long cut, stalled, healthy but some belly fat, wants bigger and leaner.
        let plan = PhasePlanner.recommend(input(waist: 88, goals: [.biggerAndStronger, .leaner], history: .longCut, maintenance: 2250, formula: 2650))
        #expect(plan.phases.first?.kind == .reverseDiet)
        #expect(plan.phases.contains { $0.kind == .leanBulk })
        #expect(plan.headline.contains("lower than expected"))
    }

    @Test func leanAndWantingSizeMeansALeanBulk() {
        let plan = PhasePlanner.recommend(input(waist: 80, goals: [.biggerAndStronger]))
        #expect(plan.phases.first?.kind == .leanBulk)
        #expect(plan.phases.first.map { $0.ratePerWeek > 0 && $0.ratePerWeek <= 0.0025 } == true)
    }

    @Test func weakForSizeMeansARecomp() {
        let plan = PhasePlanner.recommend(input(waist: 88, goals: [.biggerAndStronger], experience: .novice, strength: 32))
        #expect(plan.phases.first?.kind == .recomp)
    }

    @Test func noWaistMeansShortAndHonest() {
        var thin = input(waist: nil, goals: [.leaner])
        thin.maintenance.low = 2200
        thin.maintenance.high = 3000
        let plan = PhasePlanner.recommend(thin)
        #expect(plan.phases.first?.weeks ?? 99 <= 4)
        #expect(plan.confidence != nil)
        #expect(plan.reasons.contains { $0.contains("waist measurement") })
    }

    @Test func strengthDroppingEndsTheCut() {
        let plan = PhasePlanner.recommend(input(waist: 104, goals: [.leaner]))
        var later = input(waist: 100, goals: [.leaner], trend: .regressing)
        later.today = today.adding(weeks: 5)
        let reviewed = PhasePlanner.review(plan, input: later)
        #expect(reviewed?.phases.last?.kind == .dietBreak)
        #expect(reviewed?.headline.contains("Strength") == true)
    }

    @Test func gainingTooFastSlowsTheSurplus() {
        let plan = PhasePlanner.recommend(input(waist: 80, goals: [.biggerAndStronger]))
        var later = input(waist: 81, goals: [.biggerAndStronger], change: 0.82 * 0.8)
        later.today = today.adding(weeks: 4)
        let reviewed = PhasePlanner.review(plan, input: later)
        #expect((reviewed?.phases.first?.ratePerWeek ?? 1) < plan.phases.first!.ratePerWeek)
    }
}

@Suite("Targets and life")
struct TargetTests {
    let day = Day(year: 2026, month: 3, day: 2)
    let maintenance = MaintenanceEstimate(kcal: 2600, low: 2450, high: 2750, basis: .data, days: 21, formula: 2600)

    func plan(_ kind: PhaseKind, rate: Double) -> PhasePlan {
        PhasePlan(phases: [PlannedPhase(kind: kind, ratePerWeek: rate, weeks: 10, start: day.adding(days: -14))], headline: "",
                  reasons: [], confidence: nil, arc: "")
    }

    @Test func cutDeficitAndMacros() {
        let t = Targets.today(day: day, assessing: false, plan: plan(.cut, rate: -0.005), override: nil, maintenance: maintenance,
                              checkIn: nil, weightKg: 85, heightCm: 180, waistToHeight: 0.52, life: LifeModeEffects(), deload: false)
        let kcal = t.kcal ?? 0
        #expect(kcal < 2600 && kcal > 2600 * 0.75)
        #expect(abs(kcal - (2600 - 0.005 * 85 * 7700 / 7)) < 15)
        #expect(t.protein == 170)
        #expect((t.fat ?? 0) >= 85 * 0.6)
        #expect(t.mode == .phase)
    }

    @Test func deloadInACutIsADietBreak() {
        let t = Targets.today(day: day, assessing: false, plan: plan(.cut, rate: -0.005), override: nil, maintenance: maintenance,
                              checkIn: nil, weightKg: 85, heightCm: 180, waistToHeight: nil, life: LifeModeEffects(), deload: true)
        #expect(t.mode == .dietBreak && t.kcal == 2600)
        #expect(t.note.contains("water"))
    }

    @Test func lifeModesChangeTheAsk() {
        let vacation = LifeModes.effects(on: day, periods: [LifeModePeriod(kind: .vacation, start: day, end: day.adding(days: 6), createdBy: .liftTrack)])
        let v = Targets.today(day: day, assessing: false, plan: plan(.cut, rate: -0.005), override: nil, maintenance: maintenance,
                              checkIn: nil, weightKg: 85, heightCm: 180, waistToHeight: nil, life: vacation, deload: false)
        #expect(v.mode == .vacation && v.kcal == nil)
        let ill = LifeModes.effects(on: day, periods: [LifeModePeriod(kind: .illness(.systemic), start: day, createdBy: .macroTrack)])
        let i = Targets.today(day: day, assessing: false, plan: plan(.cut, rate: -0.005), override: nil, maintenance: maintenance,
                              checkIn: nil, weightKg: 85, heightCm: 180, waistToHeight: nil, life: ill, deload: false)
        #expect(i.mode == .illness && i.kcal == nil && i.note.contains("soup"))
        let crunch = LifeModes.effects(on: day, periods: [LifeModePeriod(kind: .crunch(CrunchDials()), start: day, end: day.adding(days: 5), createdBy: .liftTrack)])
        let c = Targets.today(day: day, assessing: false, plan: plan(.cut, rate: -0.005), override: nil, maintenance: maintenance,
                              checkIn: nil, weightKg: 85, heightCm: 180, waistToHeight: nil, life: crunch, deload: false)
        #expect(c.mode == .crunch && c.kcal == 2600 && c.protein != nil)
    }

    @Test func assessmentAsksForNoDeficit() {
        let t = Targets.today(day: day, assessing: true, plan: nil, override: nil, maintenance: maintenance, checkIn: nil, weightKg: 85,
                              heightCm: 180, waistToHeight: nil, life: LifeModeEffects(), deload: false)
        #expect(t.mode == .assessment && t.kcal == nil && t.protein != nil)
    }

    @Test func proteinUsesAHealthyReferenceWhenWaistIsHigh() {
        #expect(Targets.referenceWeight(kg: 120, heightCm: 180, waistToHeight: 0.62) < 90)
        #expect(Targets.referenceWeight(kg: 80, heightCm: 180, waistToHeight: 0.45) == 80)
    }
}

@Suite("Analysis")
struct AnalysisTests {
    @Test func assessmentLearnsAndUnloggedDaysAreUnknown() {
        let eater = SimulatedEater(maintenance: 2600, startKg: 84, logging: 0.7)
        let run = eater.run(days: 17) { _, _ in 2300 }
        let today = eater.start.adding(days: 17)
        let state = MacroState(profile: profile(), settings: MacroSettings(assessmentStart: eater.start), entries: run.entries,
                               weighIns: run.weighIns, dayStatus: run.statuses, today: today)
        let a = MacroAnalyst.analyse(state)
        #expect(a.assessment != nil)
        #expect(a.assessment?.learned.contains { $0.contains("maintenance") } == true)
        #expect(a.targets.mode == .assessment)
        // Discipline counts only known days; the unlogged ones are unknown, not misses.
        #expect(a.discipline.unknown > 0)
        #expect((a.loggingRate ?? 0) < 1)
        let summary = MacroAnalyst.nutritionSummary(state, a)
        #expect(summary.days.count == 28)
        #expect(summary.phase == nil)
    }

    @Test func planningAndCheckInsAfterTheAssessment() {
        let eater = SimulatedEater(maintenance: 2600, startKg: 84)
        let run = eater.run(days: 35) { _, _ in 2200 }
        let today = eater.start.adding(days: 35)
        var state = MacroState(profile: profile(goals: [.leaner]), settings: MacroSettings(assessmentStart: eater.start), entries: run.entries,
                               weighIns: run.weighIns, dayStatus: run.statuses, today: today)
        var a = MacroAnalyst.analyse(state)
        let plan = PhasePlanner.recommend(a.plannerInput)
        state.plan = plan
        a = MacroAnalyst.analyse(state)
        #expect(a.dueCheckIn != nil)
        #expect(a.targets.kcal != nil)
        let summary = MacroAnalyst.nutritionSummary(state, a)
        #expect(summary.phase?.source == .macroTrack)
        #expect(summary.maintenanceKcal != nil)
    }

    @Test func logAgainFavoursRecentFoodsAtThisTimeOfDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 8))!
        var entries: [FoodEntry] = []
        for d in 1...10 {
            let morning = now.addingTimeInterval(-Double(d) * 86400)
            entries.append(FoodEntry(date: morning, meal: .breakfast, name: "Oats", foodID: "usda:1", amountLabel: "80 g",
                                     nutrients: Nutrients(kcal: 300, protein: 10, carbs: 50, fat: 6), source: .search))
            entries.append(FoodEntry(date: morning.addingTimeInterval(11 * 3600), meal: .dinner, name: "Pasta", foodID: "usda:2", amountLabel: "1 plate",
                                     nutrients: Nutrients(kcal: 700, protein: 25, carbs: 100, fat: 20), source: .search))
        }
        let ranked = LogAgain.rank(entries, now: now, calendar: calendar)
        #expect(ranked.first?.template.name == "Oats")
        #expect(LogAgain.usual(.breakfast, entries: entries, before: Day(now, calendar: calendar))?.entries.first?.name == "Oats")
    }
}
