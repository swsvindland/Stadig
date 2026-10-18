import Foundation
import SystemCore
import Testing

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
                    run.entries.append(
                        FoodEntry(
                            date: date.addingTimeInterval(Double(n) * 3600), name: "Food \(n)",
                            amountLabel: "1",
                            nutrients: Nutrients(
                                kcal: eaten * share, protein: eaten * share * 0.05,
                                carbs: eaten * share * 0.11, fat: eaten * share * 0.035),
                            source: .search, updatedAt: date))
                }
                run.statuses.append(DayStatus(day: day, state: .complete))
            } else if rng.uniform() < 0.5 {
                // A partial day: some entries, marked partial, so it doesn't teach the estimate.
                run.entries.append(
                    FoodEntry(
                        date: date, name: "Partial", amountLabel: "1",
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
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func normal() -> Double {
        let u1 = max(1e-12, uniform())
        let u2 = uniform()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

func profile(goals: [OutcomeGoal] = [.biggerAndStronger], experience: TrainingExperience = .intermediate) -> SharedProfile {
    SharedProfile(
        goals: goals, schedule: TrainingSchedule(daysPerWeek: 4, minutesPerSession: 60), experience: experience, sex: .male,
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
    @Test(
        "Maintenance converges from eating and weighing in, through water and noise",
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
            let early = estimate(through: 13)
            let late = estimate(through: 27)
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
        var checkIns: [CheckIn] = [
            CheckIn(
                day: eater.start.adding(days: 20), expenditure: 2800, kcal: 2300, protein: 180, carbs: 200,
                fat: 70, status: .updated, reason: "Start")
        ]
        let phase = PlannedPhase(kind: .cut, ratePerWeek: -0.005, weeks: 12, start: eater.start.adding(days: 20))
        let run = eater.run(days: 21 + 56) { i, day in
            checkIns.last { $0.day <= day }.map(\.kcal) ?? 2400
        }
        var expenditures: [Double] = []
        for week in 1...8 {
            let day = eater.start.adding(days: 20 + week * 7)
            let trend = Weight.trend(run.weighIns.filter { $0.day < day }, through: day.adding(days: -1))
            let next = CheckIns.review(
                previous: checkIns.last, trend: trend, usable: usable(run).filter { $0.key < day }, today: day,
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

    @Test("Sparse readings on a steady loss are a trend, not misreads; a spike still is one")
    func sparseReadings() {
        let start = Day(year: 2026, month: 1, day: 5)
        func readings(_ kgs: [(day: Int, kg: Double)]) -> [WeighIn] {
            kgs.map { WeighIn(date: start.adding(days: $0.day).date().addingTimeInterval(7 * 3600), kg: $0.kg) }
        }
        // A smart scale stepped on fortnightly early in a cut: 3.5 kg from each neighbour, but between them.
        let fortnightly = Weight.trend(readings([(0, 100), (14, 96.5), (28, 93)]), through: start.adding(days: 28))
        #expect(fortnightly.outliers.isEmpty && fortnightly.points.filter { $0.scale != nil }.count == 3)
        // Monthly at about 1% a week.
        let monthly = readings((0..<5).map { (30 * $0, 100 * pow(0.96, Double($0))) })
        #expect(Weight.trend(monthly, through: start.adding(days: 120)).outliers.isEmpty)
        // A reading above both neighbours, with a gap after it, is still a misread.
        let spike = Weight.trend(readings([(0, 80), (1, 80.2), (2, 86), (12, 80.1), (13, 80)]), through: start.adding(days: 13))
        #expect(spike.outliers.map(\.kg) == [86])
    }

    @Test("A misread holds the check-in once, not every week it stays in the window")
    func misreadHoldsOnce() {
        let eater = SimulatedEater(maintenance: 2500, startKg: 80, logging: 1, noiseKg: 0.3)
        let run = eater.run(days: 50, intake: { _, _ in 2500 }, misreads: [30: 86])
        let phase = PlannedPhase(kind: .maintenance, weeks: 12, start: eater.start.adding(days: 28))
        var previous = CheckIn(
            day: eater.start.adding(days: 28), expenditure: 2500, kcal: 2500, protein: 150, carbs: 300, fat: 75,
            status: .updated, reason: "Start")
        var statuses: [CheckIn.Status] = []
        for day in [35, 42, 49].map({ eater.start.adding(days: $0) }) {
            let trend = Weight.trend(run.weighIns.filter { $0.day <= day }, through: day)
            #expect(trend.outliers.contains { $0.kg == 86 })
            previous = CheckIns.review(
                previous: previous, trend: trend, usable: usable(run).filter { $0.key < day }, today: day, phase: phase,
                weightKg: 80, referenceKg: 80, fallbackExpenditure: 2500)
            statuses.append(previous.status)
        }
        #expect(statuses == [.holding, .updated, .updated], "\(statuses)")
    }

    @Test("A misread the reading after it showed only once the check-in had run holds the next one, once")
    func misreadSeenAfterTheCheckIn() {
        let eater = SimulatedEater(maintenance: 2500, startKg: 80, logging: 1, noiseKg: 0.3)
        let run = eater.run(days: 50, intake: { _, _ in 2500 }, misreads: [34: 86])
        let phase = PlannedPhase(kind: .maintenance, weeks: 12, start: eater.start.adding(days: 28))
        var previous = CheckIn(
            day: eater.start.adding(days: 28), expenditure: 2500, kcal: 2500, protein: 150, carbs: 300, fat: 75,
            status: .updated, reason: "Start")
        func review(on day: Day, weighedFirst: Bool) -> (WeightTrend, CheckIn) {
            let trend = Weight.trend(run.weighIns.filter { weighedFirst ? $0.day <= day : $0.day < day }, through: day)
            return (
                trend,
                CheckIns.review(
                    previous: previous, trend: trend, usable: usable(run).filter { $0.key < day }, today: day,
                    phase: phase, weightKg: 80, referenceKg: 80, fallbackExpenditure: 2500)
            )
        }
        // Day 35's check-in ran before that morning's weigh-in: nothing after day 34's 86 kg yet.
        let (early, first) = review(on: eater.start.adding(days: 35), weighedFirst: false)
        #expect(early.outliers.isEmpty && !first.reason.contains("far from the ones around it"), "\(first.reason)")
        previous = first
        var statuses: [CheckIn.Status] = []
        for day in [42, 49].map({ eater.start.adding(days: $0) }) {
            let (trend, next) = review(on: day, weighedFirst: true)
            #expect(trend.outliers.contains { $0.kg == 86 })
            previous = next
            statuses.append(next.status)
        }
        #expect(statuses == [.holding, .updated], "\(statuses)")
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

    func input(
        waist: Double?, goals: [OutcomeGoal], history: DietHistory = .none, maintenance: Double = 2600, formula: Double = 2600,
        experience: TrainingExperience = .intermediate, strength: Double? = nil, trend: Trajectory? = nil, change: Double? = nil
    ) -> PlannerInput {
        PlannerInput(
            profile: profile(goals: goals, experience: experience), history: history, today: today, weightKg: 82, weeklyChange: change,
            maintenance: MaintenanceEstimate(
                kcal: maintenance, low: maintenance - 150, high: maintenance + 150, basis: .data, days: 21,
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
        let plan = PhasePlanner.recommend(
            input(waist: 88, goals: [.biggerAndStronger, .leaner], history: .longCut, maintenance: 2250, formula: 2650))
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

    @Test func gainingTooFastSlowsTheSurplus() throws {
        let plan = PhasePlanner.recommend(input(waist: 80, goals: [.biggerAndStronger]))
        var later = input(waist: 81, goals: [.biggerAndStronger], change: 0.82 * 0.8)
        later.today = today.adding(weeks: 4)
        let reviewed = try #require(PhasePlanner.review(plan, input: later))
        #expect((reviewed.phases.first?.ratePerWeek ?? 1) < plan.phases.first!.ratePerWeek)
        // Looked at again before the trend catches up, the reason isn't said twice.
        let again = try #require(PhasePlanner.review(reviewed, input: later))
        #expect(again.reasons.filter { $0 == reviewed.headline }.count == 1, "\(again.reasons)")
    }

    @Test func endingACutMidWeekStartsTheBreakToday() throws {
        let plan = PhasePlanner.recommend(input(waist: 104, goals: [.leaner]))
        var later = input(waist: 100, goals: [.leaner], trend: .regressing)
        later.today = today.adding(days: 13)
        let reviewed = try #require(PhasePlanner.review(plan, input: later))
        let cut = reviewed.phases[0]
        let rest = try #require(reviewed.phases.last)
        // The full fortnight's break from today, and the cut as it ran: to yesterday.
        #expect(rest.kind == .dietBreak && rest.start == later.today && rest.end == later.today.adding(days: 13), "\(rest)")
        #expect(cut.kind == .cut && cut.start == today && cut.end == later.today.adding(days: -1) && cut.weeks == 2, "\(cut)")
        #expect(reviewed.phase(on: later.today)?.kind == .dietBreak && reviewed.phase(on: later.today.adding(days: -1))?.kind == .cut)
        // Accepted, the plan doesn't change again the same day, and it reads back as saved.
        #expect(PhasePlanner.review(reviewed, input: later) == nil)
        let saved = try JSONDecoder().decode(PhasePlan.self, from: JSONEncoder().encode(reviewed))
        #expect(saved.phases == reviewed.phases && saved.phases[0].end == cut.end)
        // Reviewed on the cut's first day, the cut is dropped rather than given no days.
        later.today = today
        #expect(PhasePlanner.review(plan, input: later)?.phases.map(\.kind) == [.dietBreak])
    }

    @Test func aMiniCutAfterASurplusStartsToday() throws {
        let plan = PhasePlanner.recommend(input(waist: 80, goals: [.biggerAndStronger]))
        var later = input(waist: 98, goals: [.biggerAndStronger])
        later.today = today.adding(days: 30)
        let reviewed = try #require(PhasePlanner.review(plan, input: later))
        #expect(reviewed.phases.map(\.kind) == [.leanBulk, .miniCut])
        #expect(reviewed.phases[1].start == later.today && reviewed.phases[1].weeks == 5)
        #expect(reviewed.phases[0].end == later.today.adding(days: -1) && reviewed.phases[0].weeks == 5)
    }

    @Test func pastTheEndPlansAgain() throws {
        // The waist grew too, but the plan is over: a fresh recommendation from today, not the last phase stretched.
        let plan = PhasePlanner.recommend(input(waist: 80, goals: [.biggerAndStronger]))
        var later = input(waist: 98, goals: [.biggerAndStronger])
        later.today = try #require(plan.phases.last).end.adding(days: 3)
        let fresh = try #require(PhasePlanner.review(plan, input: later))
        #expect(fresh.phases.first?.start == later.today && fresh.phases.first?.kind == .miniCut, "\(fresh.phases)")
    }

    @Test func aPhaseSavedBeforeEarlyEndsStillReads() throws {
        let old = #"{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","kind":"cut","ratePerWeek":-0.005,"weeks":12,"start":"2026-03-02"}"#
        let phase = try JSONDecoder().decode(PlannedPhase.self, from: Data(old.utf8))
        #expect(phase.endedEarly == nil && phase.end == today.adding(days: 83))
    }
}

/// Weekly check-ins through a recommended plan. With no new weigh-ins maintenance stands, so only
/// the phase and the weekly cap move the calories.
@Suite("Check-ins across phases")
struct PhaseChangeTests {
    let today = Day(year: 2026, month: 3, day: 2)

    func plan(waist: Double, goals: [OutcomeGoal], kg: Double, maintenance: Double) -> PhasePlan {
        PhasePlanner.recommend(
            PlannerInput(
                profile: profile(goals: goals), history: .none, today: today, weightKg: kg, weeklyChange: nil,
                maintenance: MaintenanceEstimate(
                    kcal: maintenance, low: maintenance - 150, high: maintenance + 150,
                    basis: .data, days: 21, formula: maintenance),
                waistCm: waist))
    }

    func walk(_ plan: PhasePlan, weeks: Int, kg: Double, maintenance: Double) -> [CheckIn] {
        var checkIns = [CheckIns.start(plan, today: today, maintenance: maintenance, weightKg: kg, referenceKg: kg)]
        for week in 1...weeks {
            let day = today.adding(weeks: week)
            checkIns.append(
                CheckIns.review(
                    previous: checkIns.last, trend: .empty, usable: [:], today: day, phase: plan.phase(on: day),
                    weightKg: kg, referenceKg: kg, fallbackExpenditure: maintenance))
        }
        return checkIns
    }

    @Test("a planned diet break starts at maintenance, and the cut after it at its own calories")
    func cutDietBreakCut() {
        let plan = plan(waist: 110, goals: [.leaner], kg: 100, maintenance: 2800)
        #expect(plan.phases.map(\.kind) == [.cut, .dietBreak, .cut])
        let kcal = walk(plan, weeks: 15, kg: 100, maintenance: 2800).map(\.kcal)
        #expect(kcal[0] == 2100 && kcal[11] == 2100, "\(kcal)")
        #expect(kcal[12] == 2800 && kcal[13] == 2800, "the break is at maintenance from its first day: \(kcal)")
        #expect(kcal[14] == 2250 && kcal[15] == 2250, "\(kcal)")
    }

    @Test("a bulk after a mini-cut starts above maintenance, not 150 kcal a week up from the cut")
    func miniCutThenBulk() {
        let plan = plan(waist: 98, goals: [.biggerAndStronger], kg: 82, maintenance: 2600)
        #expect(plan.phases.map(\.kind) == [.miniCut, .leanBulk])
        let kcal = walk(plan, weeks: 6, kg: 82, maintenance: 2600).map(\.kcal)
        #expect(kcal[4] < 2600)
        #expect(kcal[5] == Targets.calories(maintenance: 2600, phase: plan.phases[1], weightKg: 82) && kcal[5] > 2600, "\(kcal)")
    }

    @Test("between a phase change and a late check-in, the new phase's calories are in force")
    func lateCheckIn() {
        let plan = plan(waist: 110, goals: [.leaner], kg: 100, maintenance: 2800)
        let breakStart = plan.phases[1].start
        let lastOfTheCut = CheckIn(
            day: breakStart.adding(days: -3), expenditure: 2750, kcal: 2100, protein: 200, carbs: 150, fat: 70,
            status: .updated, reason: "")
        func targets(on day: Day) -> DailyTargets {
            Targets.today(
                day: day, assessing: false, plan: plan, override: nil,
                maintenance: MaintenanceEstimate(kcal: 2800, low: 2650, high: 2950, basis: .data, days: 21, formula: 2800),
                checkIn: lastOfTheCut, weightKg: 100, heightCm: 180, waistToHeight: nil, life: LifeModeEffects(), deload: false)
        }
        #expect(targets(on: breakStart.adding(days: -1)).kcal == 2100)
        let onBreak = targets(on: breakStart)
        #expect(onBreak.kcal == 2750 && onBreak.note.contains("diet break"), "\(onBreak)")
    }
}

@Suite("Targets and life")
struct TargetTests {
    let day = Day(year: 2026, month: 3, day: 2)
    let maintenance = MaintenanceEstimate(kcal: 2600, low: 2450, high: 2750, basis: .data, days: 21, formula: 2600)

    func plan(_ kind: PhaseKind, rate: Double) -> PhasePlan {
        PhasePlan(
            phases: [PlannedPhase(kind: kind, ratePerWeek: rate, weeks: 10, start: day.adding(days: -14))], headline: "",
            reasons: [], confidence: nil, arc: "")
    }

    @Test func cutDeficitAndMacros() {
        let t = Targets.today(
            day: day, assessing: false, plan: plan(.cut, rate: -0.005), override: nil, maintenance: maintenance,
            checkIn: nil, weightKg: 85, heightCm: 180, waistToHeight: 0.52, life: LifeModeEffects(), deload: false)
        let kcal = t.kcal ?? 0
        #expect(kcal < 2600 && kcal > 2600 * 0.75)
        #expect(abs(kcal - (2600 - 0.005 * 85 * 7700 / 7)) < 15)
        #expect(t.protein == 170)
        #expect((t.fat ?? 0) >= 85 * 0.6)
        #expect(t.mode == .phase)
    }

    @Test func deloadInACutIsADietBreak() {
        let t = Targets.today(
            day: day, assessing: false, plan: plan(.cut, rate: -0.005), override: nil, maintenance: maintenance,
            checkIn: nil, weightKg: 85, heightCm: 180, waistToHeight: nil, life: LifeModeEffects(), deload: true)
        #expect(t.mode == .dietBreak && t.kcal == 2600)
        #expect(t.note.contains("water"))
    }

    @Test func lifeModesChangeTheAsk() {
        let vacation = LifeModes.effects(
            on: day, periods: [LifeModePeriod(kind: .vacation, start: day, end: day.adding(days: 6), createdBy: .liftTrack)])
        let v = Targets.today(
            day: day, assessing: false, plan: plan(.cut, rate: -0.005), override: nil, maintenance: maintenance,
            checkIn: nil, weightKg: 85, heightCm: 180, waistToHeight: nil, life: vacation, deload: false)
        #expect(v.mode == .vacation && v.kcal == nil)
        let ill = LifeModes.effects(on: day, periods: [LifeModePeriod(kind: .illness(.systemic), start: day, createdBy: .macroTrack)])
        let i = Targets.today(
            day: day, assessing: false, plan: plan(.cut, rate: -0.005), override: nil, maintenance: maintenance,
            checkIn: nil, weightKg: 85, heightCm: 180, waistToHeight: nil, life: ill, deload: false)
        #expect(i.mode == .illness && i.kcal == nil && i.note.contains("soup"))
        let crunch = LifeModes.effects(
            on: day, periods: [LifeModePeriod(kind: .crunch(CrunchDials()), start: day, end: day.adding(days: 5), createdBy: .liftTrack)])
        let c = Targets.today(
            day: day, assessing: false, plan: plan(.cut, rate: -0.005), override: nil, maintenance: maintenance,
            checkIn: nil, weightKg: 85, heightCm: 180, waistToHeight: nil, life: crunch, deload: false)
        #expect(c.mode == .crunch && c.kcal == 2600 && c.protein != nil)
    }

    @Test func assessmentAsksForNoDeficit() {
        let t = Targets.today(
            day: day, assessing: true, plan: nil, override: nil, maintenance: maintenance, checkIn: nil, weightKg: 85,
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
        let state = MacroState(
            profile: profile(), settings: MacroSettings(assessmentStart: eater.start), entries: run.entries,
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
        var state = MacroState(
            profile: profile(goals: [.leaner]), settings: MacroSettings(assessmentStart: eater.start), entries: run.entries,
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

    /// Five weeks of full days at 2,600 kcal and 140 g protein, weighed every morning at 84 kg:
    /// three weeks of a lean bulk, then a cut. Today has one entry so far.
    func bulkThenCut(lifeModes: [LifeModePeriod] = []) -> MacroState {
        let start = Day(year: 2026, month: 3, day: 2)
        let today = start.adding(days: 35)
        var entries: [FoodEntry] = []
        var weighIns: [WeighIn] = []
        var statuses: [DayStatus] = []
        for day in DayRange(start, today.adding(days: -1)).days {
            for hour in [8.0, 12, 15, 19] {
                let date = day.date().addingTimeInterval(hour * 3600)
                entries.append(
                    FoodEntry(
                        date: date, name: "Meal", amountLabel: "1", nutrients: Nutrients(kcal: 650, protein: 35, carbs: 70, fat: 22),
                        source: .search, updatedAt: date))
            }
            weighIns.append(WeighIn(date: day.date().addingTimeInterval(7 * 3600), kg: 84))
            statuses.append(DayStatus(day: day, state: .complete))
        }
        entries.append(
            FoodEntry(
                date: today.date().addingTimeInterval(8 * 3600), name: "Breakfast", amountLabel: "1",
                nutrients: Nutrients(kcal: 400, protein: 20, carbs: 50, fat: 10), source: .search))
        let phases = [PlannedPhase(kind: .leanBulk, weeks: 3, start: start), PlannedPhase(kind: .cut, weeks: 8, start: start.adding(days: 21))]
        let plan = PhasePlan(phases: phases, headline: "", reasons: [], confidence: nil, arc: "", created: start.date())
        return MacroState(
            profile: profile(), settings: MacroSettings(assessmentStart: start.adding(days: -21)), entries: entries,
            weighIns: weighIns, dayStatus: statuses, plan: plan, lifeModes: lifeModes, today: today,
            now: today.date().addingTimeInterval(9 * 3600))
    }

    @Test func publishedDaysAreJudgedByTheirOwnTargets() throws {
        let state = bulkThenCut()
        let days = MacroAnalyst.nutritionSummary(state, MacroAnalyst.analyse(state)).days
        func published(_ offset: Int) throws -> NutritionDay { try #require(days.first { $0.day == state.today.adding(days: offset) }) }
        // 140 g met the bulk's 145 g (within 10%) but not the cut's 170 g.
        #expect(try published(-20).proteinHit == true, "a bulk day, judged as a bulk day")
        #expect(try published(-7).proteinHit == false, "a cut day")
        // Today so far is logged, but not judged.
        let today = try published(0)
        #expect(today.logged && today.proteinHit == nil && today.caloriesHit == nil)
    }

    @Test func aVacationTodayDoesNotUnjudgeTheMonthBefore() {
        let state = bulkThenCut()
        let trip = LifeModePeriod(kind: .vacation, start: state.today, end: state.today.adding(days: 6), createdBy: .liftTrack)
        let away = bulkThenCut(lifeModes: [trip])
        let a = MacroAnalyst.analyse(away)
        #expect(a.targets.mode == .vacation)
        let days = MacroAnalyst.nutritionSummary(away, a).days
        let known = days.filter { $0.day < state.today }
        #expect(known.count == 27 && known.allSatisfy { $0.logged && $0.proteinHit != nil }, "\(known.filter { $0.proteinHit == nil }.map(\.day))")
        let home = MacroAnalyst.nutritionSummary(state, MacroAnalyst.analyse(state)).days.filter { $0.day < state.today }
        #expect(known.map(\.proteinHit) == home.map(\.proteinHit), "the same days, judged the same, home or away")
    }

    @Test func aRejectedReadingIsNeverTheWeight() {
        let today = Day(year: 2026, month: 3, day: 2)
        // A typo and a reading the person said to ignore are all there is.
        let typo = WeighIn(date: today.date().addingTimeInterval(7 * 3600), kg: 18)
        let ignored = WeighIn(date: today.adding(days: -1).date().addingTimeInterval(7 * 3600), kg: 140, excluded: true)
        let state = MacroState(profile: profile(), settings: MacroSettings(assessmentStart: today), weighIns: [typo, ignored], today: today)
        #expect(MacroAnalyst.analyse(state).plannerInput.weightKg == 82, "the typical weight, not 18 or 140")
        // A good reading is used even when it isn't the last one stored.
        let good = WeighIn(date: today.adding(days: 3).date(), kg: 90)
        let later = MacroState(profile: profile(), settings: MacroSettings(assessmentStart: today), weighIns: [good, typo, ignored], today: today)
        #expect(MacroAnalyst.analyse(later).plannerInput.weightKg == 90)
    }

    @Test func aDaysNewerCheckInIsInForceAndHasTheDaysID() {
        let day = Day(year: 2026, month: 3, day: 2)
        let morning = CheckIn(
            day: day, expenditure: 2600, kcal: 2100, protein: 170, carbs: 200, fat: 70, status: .updated, reason: "Weekly",
            updatedAt: day.date().addingTimeInterval(8 * 3600))
        let started = CheckIn(
            day: day, expenditure: 2600, kcal: 2400, protein: 170, carbs: 270, fat: 70, status: .updated, reason: "New plan",
            updatedAt: day.date().addingTimeInterval(15 * 3600))
        // The store hands back the newest first.
        let state = MacroState(profile: profile(), settings: MacroSettings(), checkIns: [started, morning], today: day)
        #expect(state.checkIns.last?.kcal == 2400)
        // Check-ins made on two devices the same day are one record.
        let week = day.adding(days: 7)
        let next = CheckIns.review(
            previous: started, trend: .empty, usable: [:], today: week, phase: nil, weightKg: 84, referenceKg: 84,
            fallbackExpenditure: 2600)
        #expect(next.id == CheckIn.id(for: week) && CheckIn.id(for: week) != CheckIn.id(for: day))
        let plan = PhasePlan(phases: [PlannedPhase(kind: .cut, weeks: 8, start: day)], headline: "", reasons: [], confidence: nil, arc: "")
        let first = CheckIns.start(plan, today: day, maintenance: 2600, weightKg: 84, referenceKg: 84)
        #expect(first.id == CheckIn.id(for: day) && first.kcal == Targets.calories(maintenance: 2600, phase: plan.phases[0], weightKg: 84))
    }

    @Test func logAgainFavoursRecentFoodsAtThisTimeOfDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 8))!
        var entries: [FoodEntry] = []
        for d in 1...10 {
            let morning = now.addingTimeInterval(-Double(d) * 86400)
            entries.append(
                FoodEntry(
                    date: morning, name: "Oats", foodID: "usda:1", amountLabel: "80 g",
                    nutrients: Nutrients(kcal: 300, protein: 10, carbs: 50, fat: 6), source: .search))
            entries.append(
                FoodEntry(
                    date: morning.addingTimeInterval(11 * 3600), name: "Pasta", foodID: "usda:2", amountLabel: "1 plate",
                    nutrients: Nutrients(kcal: 700, protein: 25, carbs: 100, fat: 20), source: .search))
        }
        let ranked = LogAgain.rank(entries, now: now, calendar: calendar)
        #expect(ranked.first?.template.name == "Oats")
        // A single food isn't a moment worth copying whole; oats with coffee is.
        #expect(LogAgain.usualMoment(near: now, entries: entries, calendar: calendar) == nil)
        let coffee = (1...3).map { d in
            FoodEntry(
                date: now.addingTimeInterval(-Double(d) * 86400 + 300), name: "Coffee", amountLabel: "1 cup",
                nutrients: Nutrients(kcal: 5, protein: 0, carbs: 0, fat: 0), source: .search)
        }
        let usual = LogAgain.usualMoment(near: now, entries: entries + coffee, calendar: calendar)
        #expect(usual?.entries.map(\.name) == ["Oats", "Coffee"])
        #expect(usual?.start == now.addingTimeInterval(-86400), "yesterday's, the most recent")
        // Not at dinner time.
        #expect(LogAgain.usualMoment(near: now.addingTimeInterval(5 * 3600), entries: entries + coffee, calendar: calendar) == nil)
    }

    @Test func aDayIsMomentsHoweverManyThereAre() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func at(_ minutes: Double) -> FoodEntry {
            FoodEntry(
                date: start.addingTimeInterval(minutes * 60), name: "F\(Int(minutes))", amountLabel: "1",
                nutrients: Nutrients(kcal: 100, protein: 5, carbs: 10, fat: 3), source: .search)
        }
        // Three foods at breakfast, a snack, lunch, two more snacks and a late dinner: five moments.
        let day = [at(0), at(5), at(20), at(150), at(300), at(310), at(420), at(600), at(605)].shuffled()
        let moments = Timeline.moments(day)
        #expect(moments.map(\.entries.count) == [3, 1, 2, 1, 2])
        #expect(moments.first?.nutrients.kcal == 300)
        #expect(moments.map(\.start) == moments.map(\.start).sorted())
    }
}
