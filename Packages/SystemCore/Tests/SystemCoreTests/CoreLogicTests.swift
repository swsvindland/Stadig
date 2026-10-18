import Foundation
import Testing
@testable import SystemCore

@Suite("Days")
struct DayTests {
    @Test func arithmeticAndWeekdays() {
        let day = Day(year: 2026, month: 10, day: 15)
        #expect(day.weekday == .thursday)
        #expect(day.iso == "2026-10-15")
        #expect(Day(iso: "2026-10-15") == day)
        #expect(day.adding(days: 17) == Day(year: 2026, month: 11, day: 1))
        #expect(Day(year: 2024, month: 3, day: 1).adding(days: -1) == Day(year: 2024, month: 2, day: 29))
        #expect(day.startOfWeek == Day(year: 2026, month: 10, day: 12))
        #expect(Day(ordinal: 0).iso == "1970-01-01")
        let data = try! JSONEncoder().encode([day])
        #expect(String(data: data, encoding: .utf8) == "[\"2026-10-15\"]")
    }
}

@Suite("Strength scoring")
struct StrengthScoringTests {
    @Test func anchorsAtReferenceBodyweight() {
        // A 100 kg bench at 80 kg bodyweight is 1.25 × BW: the intermediate anchor.
        let score = StrengthStandards.score(.horizontalPress, oneRepMaxKg: 100, bodyweightKg: 80, sex: .male)
        #expect(abs(score - 60) < 0.01)
        #expect(StrengthStandards.level(for: score) == "Intermediate")
        let inverse = StrengthStandards.oneRepMax(for: 60, .horizontalPress, bodyweightKg: 80, sex: .male)
        #expect(abs(inverse - 100) < 0.1)
    }

    @Test func heavierLiftersNeedASmallerMultiple() {
        let light = StrengthStandards.score(.squat, oneRepMaxKg: 140, bodyweightKg: 70, sex: .male)
        let heavy = StrengthStandards.score(.squat, oneRepMaxKg: 200, bodyweightKg: 100, sex: .male)
        // Both lift 2× bodyweight. Strength per kg falls as bodyweight rises, so the heavier
        // lifter's 2× is the bigger feat and scores higher.
        #expect(heavy > light)
        #expect(StrengthStandards.score(.squat, oneRepMaxKg: 0, bodyweightKg: 80, sex: .male) == 0)
    }

    @Test func imbalancePriorities() {
        let day = Day(year: 2026, month: 1, day: 1)
        let profile = StrengthProfile(categories: [
            CategoryScore(category: .squat, oneRepMaxKg: 160, score: 82, exerciseID: "a", day: day),
            CategoryScore(category: .floorPull, oneRepMaxKg: 190, score: 80, exerciseID: "b", day: day),
            CategoryScore(category: .horizontalPress, oneRepMaxKg: 80, score: 55, exerciseID: "c", day: day),
            CategoryScore(category: .verticalPull, oneRepMaxKg: 95, score: 52, exerciseID: "d", day: day),
            CategoryScore(category: .verticalPress, oneRepMaxKg: 50, score: 50, exerciseID: "e", day: day),
        ], bodyweightKg: 80, sex: .male)
        let priorities = profile.priorities
        #expect(priorities.contains { $0.target == .region(.upperPush) && $0.emphasis > 0 })
        #expect(priorities.contains { $0.target == .region(.lower) && $0.emphasis < 0 })
        #expect(profile.weakest?.category == .verticalPress)
        #expect(abs((profile.overall ?? 0) - 63.8) < 0.01)
    }

    @Test func estimatesWeighRatingsByTrust() {
        let set = LoggedSet(exerciseID: "x", kind: .working, loadKg: 100, reps: 5, rating: .green)
        let low = StrengthEstimator.estimate(set, basis: .external, trust: TrustState(prior: 0.1))!
        let high = StrengthEstimator.estimate(set, basis: .external, trust: TrustState(prior: 0.9))!
        let floor = OneRepMax.epley(100, reps: 5)
        #expect(low > floor && high > low)
        let repOut = LoggedSet(exerciseID: "x", kind: .repOut, loadKg: 100, reps: 8)
        #expect(StrengthEstimator.estimate(repOut, basis: .external, trust: TrustState(prior: 0.1)) == OneRepMax.epley(100, reps: 8))
        let warmup = LoggedSet(exerciseID: "x", kind: .warmup, loadKg: 60, reps: 5)
        #expect(StrengthEstimator.estimate(warmup, basis: .external, trust: TrustState(prior: 0.5)) == nil)
    }

    @Test func pullUpsCountTheBody() {
        let set = LoggedSet(exerciseID: "pull-up", kind: .repOut, loadKg: 10, reps: 5, bodyweightKg: 80)
        #expect(StrengthEstimator.estimate(set, basis: .bodyweightPlus, trust: TrustState(prior: 0.5)) == OneRepMax.epley(90, reps: 5))
        #expect(OneRepMax.effectiveLoad(20, basis: .assisted, bodyweightKg: 80) == 60)
    }
}

@Suite("Trust calibration")
struct TrustTests {
    @Test func repOutRevealsSandbagging() {
        let date = Date()
        let sets = [
            LoggedSet(exerciseID: "machine-chest-press", date: date, kind: .working, loadKg: 50, reps: 8, rating: .orange),
            LoggedSet(exerciseID: "machine-chest-press", date: date, kind: .repOut, loadKg: 50, reps: 14),
        ]
        let observations = Calibration.observations(sets: sets, exercise: TestExercise.chestPress)
        #expect(observations.count == 1)
        #expect((observations.first?.error ?? 0) > 2)
        #expect(observations.first?.source == .repOut)
    }

    @Test func accurateRatingIsConfirmed() {
        let date = Date()
        let sets = [
            LoggedSet(exerciseID: "machine-chest-press", date: date, kind: .working, loadKg: 50, reps: 10, rating: .orange),
            LoggedSet(exerciseID: "machine-chest-press", date: date, kind: .repOut, loadKg: 50, reps: 11),
        ]
        let observations = Calibration.observations(sets: sets, exercise: TestExercise.chestPress)
        #expect(observations.map(\.error) == [0])
        var trust = TrustState(experience: .novice)
        let before = trust.score
        trust.record(observations)
        #expect(trust.score > before)
    }

    @Test func heavierLaterSetShowsMoreWasLeft() {
        let date = Date()
        let sets = [
            LoggedSet(exerciseID: "machine-chest-press", date: date, kind: .working, loadKg: 40, reps: 10, rating: .orange),
            LoggedSet(exerciseID: "machine-chest-press", date: date, kind: .working, loadKg: 55, reps: 10, rating: .orange),
        ]
        let observations = Calibration.observations(sets: sets, exercise: TestExercise.chestPress)
        #expect(observations.count == 1)
        #expect(observations.first?.source == .verification)
        #expect((observations.first?.error ?? 0) > 1)
    }

    @Test func overconfidenceLowersTrust() {
        var trust = TrustState(experience: .experienced)
        let start = trust.score
        let day = Day(year: 2026, month: 1, day: 1)
        trust.record((0..<8).map { _ in
            CalibrationObservation(day: day, exerciseID: "x", rating: .green, error: -3, source: .repOut, tier: .safeToFail)
        })
        #expect(trust.score < start - 0.2)
        #expect(trust.bias < -1)
        #expect(trust.reserve(for: .green) < SetRating.green.nominalRIR)
    }

    @Test func freeWeightEvidenceCountsLess() {
        let day = Day(year: 2026, month: 1, day: 1)
        var machine = TrustState(prior: 0.5)
        var barbell = TrustState(prior: 0.5)
        machine.record([CalibrationObservation(day: day, exerciseID: "m", rating: .orange, error: 0, source: .repOut, tier: .safeToFail)])
        barbell.record([CalibrationObservation(day: day, exerciseID: "b", rating: .orange, error: 0, source: .repOut, tier: .failWithSetup)])
        #expect(machine.score > barbell.score)
    }
}

@Suite("Autoregulation")
struct AutoregulationTests {
    let context = Autoregulation.Context(exercise: TestExercise.chestPress, increments: FixedIncrements(stepKg: 5),
                                         trust: TrustState(prior: 0.8), repRange: RepRange(8, 12))
    let planned = SetPrescription(kind: .working, loadKg: 50, targetReps: 10, targetRIR: 2)

    @Test func greenBumps() {
        let done = LoggedSet(exerciseID: "machine-chest-press", kind: .working, loadKg: 50, reps: 10, rating: .green)
        let adjustment = Autoregulation.next(after: done, planned: planned, context: context)
        #expect(adjustment.kind == .bump)
        #expect((adjustment.next.loadKg ?? 0) > 50)
        #expect((adjustment.next.loadKg ?? 0) <= 60)
    }

    @Test func orangeHolds() {
        let done = LoggedSet(exerciseID: "machine-chest-press", kind: .working, loadKg: 50, reps: 10, rating: .orange)
        let adjustment = Autoregulation.next(after: done, planned: planned, context: context)
        #expect(adjustment.kind == .hold)
        #expect(adjustment.next.loadKg == 50)
    }

    @Test func orangeIsVerifiedWhenTrustIsLow() {
        var low = context
        low.trust = TrustState(prior: 0.2)
        let done = LoggedSet(exerciseID: "machine-chest-press", kind: .working, loadKg: 50, reps: 10, rating: .orange)
        let adjustment = Autoregulation.next(after: done, planned: planned, context: low)
        #expect(adjustment.kind == .verify)
        #expect(adjustment.next.loadKg == 55)
        low.verifiedAlready = true
        #expect(Autoregulation.next(after: done, planned: planned, context: low).kind == .hold)
        // Racked barbell lifts only with safeties set.
        var bench = low
        bench.exercise = TestExercise.bench
        bench.verifiedAlready = false
        #expect(Autoregulation.next(after: done, planned: planned, context: bench).kind == .hold)
        bench.hasSafeties = true
        #expect(Autoregulation.next(after: done, planned: planned, context: bench).kind == .verify)
    }

    @Test func redDrops() {
        let done = LoggedSet(exerciseID: "machine-chest-press", kind: .working, loadKg: 50, reps: 6, targetReps: 10, rating: .red)
        let adjustment = Autoregulation.next(after: done, planned: planned, context: context)
        #expect(adjustment.kind == .drop)
        #expect((adjustment.next.loadKg ?? 99) < 50)
        #expect(adjustment.message.contains("just data"))
    }

    @Test func findingWeightSettles() {
        let finding = SetPrescription(kind: .findingWeight, loadKg: nil, targetReps: 10, targetRIR: 2)
        let easy = LoggedSet(exerciseID: "machine-chest-press", kind: .findingWeight, loadKg: 30, reps: 10, rating: .green)
        let up = Autoregulation.next(after: easy, planned: finding, context: context)
        #expect(up.next.kind == .findingWeight)
        #expect((up.next.loadKg ?? 0) >= 35)
        let right = LoggedSet(exerciseID: "machine-chest-press", kind: .findingWeight, loadKg: 45, reps: 10, rating: .orange)
        let found = Autoregulation.next(after: right, planned: finding, context: context)
        #expect(found.kind == .found)
        #expect(found.next.kind == .working)
        #expect(found.next.loadKg == 45)
    }

    @Test func assistedGetsHarderByRemovingAssistance() {
        var assisted = TestExercise.pullUp
        assisted.loadBasis = .assisted
        let ctx = Autoregulation.Context(exercise: assisted, increments: FixedIncrements(stepKg: 5), trust: TrustState(prior: 0.8),
                                         repRange: RepRange(6, 10))
        let done = LoggedSet(exerciseID: "pull-up", kind: .working, loadKg: 30, reps: 8, rating: .green, bodyweightKg: 80)
        let adjustment = Autoregulation.next(after: done, planned: SetPrescription(kind: .working, loadKg: 30, targetReps: 8, targetRIR: 2), context: ctx)
        #expect((adjustment.next.loadKg ?? 99) < 30)
    }
}

@Suite("Progression")
struct ProgressionTests {
    @Test func firstTimeFindsAWeight() {
        let context = ProgressionContext(exercise: TestExercise.chestPress, increments: FixedIncrements(stepKg: 5), trust: TrustState(prior: 0.3),
                                         phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: [])
        let p = Progression.prescribe(SlotTarget(sets: 3, repRange: RepRange(8, 12), targetRIR: 2), context)
        #expect(p.mode == .findingWeight)
        #expect(p.sets.allSatisfy { $0.loadKg == nil && $0.targetReps == 10 })
    }

    @Test func deloadHalvesSetsAndLightens() {
        let date = Date()
        let history = (0..<3).map { _ in LoggedSet(exerciseID: "barbell-bench-press", date: date, kind: .working, loadKg: 100, reps: 6, rating: .orange) }
        let context = ProgressionContext(exercise: TestExercise.bench, increments: FixedIncrements(stepKg: 2.5), trust: TrustState(prior: 0.6),
                                         phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: history)
        let p = Progression.prescribe(SlotTarget(sets: 4, repRange: RepRange(5, 8), targetRIR: 1, deload: true), context)
        #expect(p.mode == .deload)
        #expect(p.sets.count == 2)
        #expect(p.sets.allSatisfy { ($0.loadKg ?? 999) < 100 })
    }

    @Test func coarseIncrementsClimbReps() {
        let date = Date()
        let history = (0..<3).map { _ in LoggedSet(exerciseID: "db", date: date, kind: .working, loadKg: 10, reps: 10, rating: .orange) }
        var exercise = TestExercise.chestPress
        exercise.equipment = .dumbbell
        exercise.loadBasis = .perHand
        let context = ProgressionContext(exercise: exercise, increments: FixedIncrements(stepKg: 2), trust: TrustState(prior: 0.6),
                                         phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: history)
        let p = Progression.prescribe(SlotTarget(sets: 3, repRange: RepRange(8, 12), targetRIR: 2), context)
        #expect(p.mode == .reps)
        #expect(p.sets.first?.targetReps == 11)
        #expect(p.sets.first?.loadKg == 10)
    }

    @Test func injuryRampLightensTheLoad() {
        let date = Date()
        let history = (0..<3).map { _ in LoggedSet(exerciseID: "barbell-bench-press", date: date, kind: .working, loadKg: 100, reps: 6, rating: .orange) }
        let full = ProgressionContext(exercise: TestExercise.bench, increments: FixedIncrements(stepKg: 2.5), trust: TrustState(prior: 0.6),
                                      phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: history)
        var ramp = full
        ramp.loadFactor = 0.7
        let target = SlotTarget(sets: 3, repRange: RepRange(5, 8), targetRIR: 2)
        #expect((Progression.prescribe(target, ramp).sets.first?.loadKg ?? 999) < (Progression.prescribe(target, full).sets.first?.loadKg ?? 0))
    }

    @Test func rirFallsAcrossTheBlock() {
        #expect(Progression.targetRIR(week: 0, of: 5) == 3)
        #expect(Progression.targetRIR(week: 4, of: 5) == 0.5)
        #expect(Progression.targetRIR(week: 2, of: 5) > Progression.targetRIR(week: 3, of: 5))
    }

    @Test func rampUpSetsLeadToTheWorkingLoad() {
        let sets = Progression.rampUp(to: 100, reps: 5, exercise: TestExercise.bench, increments: FixedIncrements(stepKg: 2.5), bodyweightKg: 80)
        #expect(sets.count == 3)
        #expect(sets.allSatisfy { $0.kind == .warmup && ($0.loadKg ?? 0) < 100 })
        #expect(Progression.rampUp(to: 40, reps: 10, exercise: TestExercise.legExtension, increments: FixedIncrements(stepKg: 5), bodyweightKg: 80).isEmpty)
    }
}

@Suite("Blocks and life modes")
struct ScheduleTests {
    let start = Day(year: 2026, month: 3, day: 2)

    @Test func blockLengthByContext() {
        #expect(BlockScheduler.loadingWeeks(phase: NutritionPhase.assumedMaintenance.effects, experience: .intermediate) == 5)
        #expect(BlockScheduler.loadingWeeks(phase: NutritionPhase(kind: .cut, source: .macroTrack).effects, experience: .intermediate) == 4)
        #expect(BlockScheduler.loadingWeeks(phase: NutritionPhase(kind: .miniCut, source: .macroTrack).effects, experience: .intermediate) == 3)
        #expect(BlockScheduler.loadingWeeks(phase: NutritionPhase(kind: .leanBulk, source: .macroTrack).effects, experience: .novice) == 7)
    }

    @Test func vacationNearTheDeloadBecomesIt() {
        let block = TrainingBlock(kind: .standard, start: start, loadingWeeks: 5)
        let vacation = DayRange(start.adding(days: 30), start.adding(days: 38))
        let reflowed = BlockScheduler.reflow(block, vacations: [vacation])
        #expect(reflowed.effectiveDeloadStart == vacation.start)
        #expect(reflowed.end == vacation.end)
        #expect(reflowed.deloadReason?.contains("becomes the deload") == true)
        #expect(reflowed.week(of: start.adding(days: 31)) == .deload)
    }

    @Test func earlyVacationCutsTheBlockShort() {
        let block = TrainingBlock(kind: .standard, start: start, loadingWeeks: 5)
        let vacation = DayRange(start.adding(days: 10), start.adding(days: 16))
        let reflowed = BlockScheduler.reflow(block, vacations: [vacation])
        #expect(reflowed.end == vacation.end)
        #expect(reflowed.deloadReason?.contains("fresh block") == true)
    }

    @Test func vacationInTheFirstDaysMovesTheStart() {
        let block = TrainingBlock(kind: .standard, start: start, loadingWeeks: 5)
        let vacation = DayRange(start.adding(days: 1), start.adding(days: 7))
        let reflowed = BlockScheduler.reflow(block, vacations: [vacation])
        #expect(reflowed.start == start.adding(days: 8))
        #expect(reflowed.loadingWeeks == 5)
    }

    @Test func shortTripsDontReshape() {
        let block = TrainingBlock(kind: .standard, start: start, loadingWeeks: 5)
        let reflowed = BlockScheduler.reflow(block, vacations: [DayRange(start.adding(days: 12), start.adding(days: 13))])
        #expect(reflowed == block)
    }

    @Test func earlyDeloadFromFatigue() {
        let block = TrainingBlock(kind: .standard, start: start, loadingWeeks: 5)
        let fatigue = FatigueAssessment(status: .overreached, loadRatio: 1.6, acute: 10, chronic: 6, signals: ["Sleep is short."],
                                        action: .deloadEarly, budgetFactor: 0.7)
        #expect(BlockScheduler.deloadEarly(block, today: start.adding(days: 8), fatigue: fatigue) == nil)
        let moved = BlockScheduler.deloadEarly(block, today: start.adding(days: 17), fatigue: fatigue)
        #expect(moved?.effectiveDeloadStart == start.adding(days: 17))
        #expect(moved?.checkInDay == start.adding(days: 23))
    }

    @Test func lifeModeEffects() {
        let vacation = LifeModePeriod(kind: .vacation, start: start, end: start.adding(days: 6), createdBy: .liftTrack)
        let during = LifeModes.effects(on: start.adding(days: 2), periods: [vacation])
        #expect(!during.trainingExpected && during.disciplineExempt)
        let after = LifeModes.effects(on: start.adding(days: 9), periods: [vacation])
        #expect(after.reentry && after.trainingExpected && !after.disciplineExempt)

        let crunch = LifeModePeriod(kind: .crunch(CrunchDials(minutesAvailable: 20, equipment: .hotelGym)), start: start,
                                    end: start.adding(days: 10), createdBy: .macroTrack)
        let c = LifeModes.effects(on: start.adding(days: 1), periods: [crunch])
        #expect(c.minimumEffectiveDose && c.maxMinutes == 20 && c.equipment == .hotelGym && !c.disciplineExempt && c.lifeStress > 0)

        let cold = LifeModePeriod(kind: .illness(.aboveNeck), start: start, createdBy: .liftTrack)
        let i = LifeModes.effects(on: start.adding(days: 3), periods: [cold])
        #expect(i.lightOnly && i.trainingExpected && i.disciplineExempt)
        let flu = LifeModePeriod(kind: .illness(.systemic), start: start, createdBy: .liftTrack)
        #expect(!LifeModes.effects(on: start, periods: [flu]).trainingExpected)
    }

    @Test func injuryFiltersAndRamps() {
        let injury = Injury(parts: [InjuredPart(.shoulder, side: .right)], severity: .moderate)
        #expect(injury.excludes(TestExercise.bench))
        #expect(injury.excludes(TestExercise.chestPress))
        #expect(!injury.excludes(TestExercise.legExtension))
        var allowed = injury
        allowed.allowed = [TestExercise.chestPress.id]
        #expect(!allowed.excludes(TestExercise.chestPress))
        #expect(!Injury(parts: [InjuredPart(.shoulder)], severity: .mild).excludes(TestExercise.chestPress))

        let period = LifeModePeriod(kind: .injury(injury), start: start, end: start.adding(days: 20), createdBy: .liftTrack)
        #expect(LifeModes.effects(on: start.adding(days: 5), periods: [period]).excludes(TestExercise.bench))
        let ramp = LifeModes.effects(on: start.adding(days: 25), periods: [period])
        #expect(!ramp.excludes(TestExercise.bench))
        let factor = ramp.loadFactor(for: TestExercise.bench)
        #expect(factor > 0.6 && factor < 1)
        #expect(ramp.loadFactor(for: TestExercise.legExtension) == 1)
    }
}

@Suite("Discipline")
struct DisciplineTests {
    let today = Day(year: 2026, month: 5, day: 31)

    @Test func oneMissInFourWeeksIsInTheZone() {
        let window = Discipline.window(ending: today)
        var items = (0..<12).map { i in AdherenceItem(day: window.start.adding(days: i * 2), kind: .session, label: "Session", done: true) }
        items[3].done = false
        let score = Discipline.score(items, exempt: [], window: window)
        #expect(abs((score.rate ?? 0) - 11.0 / 12.0) < 0.001)
        #expect(score.band == .above)
        #expect(score.credit == 1)
        items[5].done = false
        items[7].done = false
        let lower = Discipline.score(items, exempt: [], window: window)
        #expect(lower.band == .below)
        #expect((lower.credit ?? 1) < 1)
    }

    @Test func exemptAndUnknownDaysDontCount() {
        let window = Discipline.window(ending: today)
        let items = [
            AdherenceItem(day: window.start, kind: .session, label: "S", done: false),
            AdherenceItem(day: window.start.adding(days: 1), kind: .mealLog, label: "M", done: nil),
            AdherenceItem(day: window.start.adding(days: 2), kind: .session, label: "S", done: true),
        ]
        let score = Discipline.score(items, exempt: [window.start], window: window)
        #expect(score.planned == 1 && score.completed == 1 && score.unknown == 1 && score.exemptDays == 1)
        #expect(score.rate == 1)
    }
}

@Suite("Fatigue Budget")
struct FatigueTests {
    let today = Day(year: 2026, month: 6, day: 30)

    func steadyEvents(days: Int = 28, systemic: Double = 4) -> [FatigueEvent] {
        stride(from: 0, to: days, by: 2).map { FatigueEvent(day: today.adding(days: -$0), load: FatigueLoad(systemic: systemic)) }
    }

    @Test func steadyTrainingIsProductive() {
        let assessment = FatigueBudget.assess(events: steadyEvents(), recovery: [], lifeStress: [:], performanceTrend: 0.01, today: today)
        #expect(assessment.status == .productive || assessment.status == .fresh)
        #expect(assessment.action == .none)
    }

    @Test func beatUpAndStalledReducesSystemicCost() {
        var events = steadyEvents()
        for i in events.indices where events[i].day > today.adding(days: -14) {
            events[i].feedback = SessionFeedback(soreness: 3, jointPain: [], energy: 2)
        }
        let recovery = (0..<7).map { RecoveryDay(day: today.adding(days: -$0), sleepHours: 7.5) }
        let assessment = FatigueBudget.assess(events: events, recovery: recovery, lifeStress: [:], performanceTrend: 0, today: today)
        #expect(assessment.status == .strained)
        #expect(assessment.action == .reduceSystemic)
    }

    @Test func stackedSignalsCallForAnEarlyDeload() {
        var events = steadyEvents()
        for i in events.indices where events[i].day > today.adding(days: -14) {
            events[i].feedback = SessionFeedback(soreness: 3, jointPain: [.knee], energy: 1)
        }
        let recovery = (0..<35).map { i in
            RecoveryDay(day: today.adding(days: -i), sleepHours: i < 7 ? 5.2 : 7.5, hrv: i < 7 ? 35 : 55, restingHeartRate: i < 7 ? 64 : 56)
        }
        let assessment = FatigueBudget.assess(events: events, recovery: recovery, lifeStress: [:], performanceTrend: -0.02, today: today)
        #expect(assessment.status == .overreached)
        #expect(assessment.action == .deloadEarly)
        #expect(assessment.budgetFactor < 1)
    }

    @Test func failureSetsCostMoreOnDeadlifts() {
        let normal = FatigueBudget.cost(of: LoggedSet(exerciseID: "d", kind: .working, loadKg: 150, reps: 5, rating: .orange), exercise: TestExercise.deadlift)
        let failed = FatigueBudget.cost(of: LoggedSet(exerciseID: "d", kind: .repOut, loadKg: 150, reps: 8), exercise: TestExercise.deadlift)
        #expect(failed.systemic > normal.systemic * 1.8)
    }

    @Test func outsideTrainingSpendsTheSameBudget() {
        let phase = NutritionPhase.assumedMaintenance.effects
        let none = FatigueBudget.weeklySystemicBudget(experience: .intermediate, daysPerWeek: 4, phase: phase, assessment: nil, outside: .zero)
        let bjj = ActivityLog(type: .bjj, start: Date(), minutes: 90, martialArts: MartialArtsDetails(classType: .sparring, sparringRounds: 6))
        let withBJJ = FatigueBudget.weeklySystemicBudget(experience: .intermediate, daysPerWeek: 4, phase: phase, assessment: nil,
                                                         outside: bjj.fatigue + bjj.fatigue)
        #expect(withBJJ < none)
        #expect(withBJJ >= none * 0.45)
        let cut = FatigueBudget.weeklySystemicBudget(experience: .intermediate, daysPerWeek: 4,
                                                     phase: NutritionPhase(kind: .cut, source: .selfReported).effects, assessment: nil, outside: .zero)
        #expect(cut < none)
    }
}

@Suite("Agility, physique, endurance")
struct StatsTests {
    @Test func weakestMobilityTestBecomesTheLimiter() {
        let day = Day(year: 2026, month: 1, day: 1)
        let analysis = Agility.analyse([
            MobilityResult(test: .kneeToWall, day: day, value: 11),
            MobilityResult(test: .hip9090, day: day, value: 1),
            MobilityResult(test: .sitAndReach, day: day, value: 2),
        ])
        #expect(analysis.limiter == .hips)
        #expect(analysis.limiterTest == .hip9090)
        let painful = Agility.analyse([MobilityResult(test: .overheadReach, day: day, value: 1, painful: true)])
        #expect(painful.seePhysio == [.overheadReach])
    }

    @Test func physiqueGapsSpeakInProportions() {
        let day = Day(year: 2026, month: 1, day: 1)
        let analysis = Physique.analyse([BodyMeasurements(day: day, neckCm: 39, shouldersCm: 112, waistCm: 86, armCm: 36)],
                                        sex: .male, heightCm: 180)
        #expect(analysis.gaps.first?.region == .shoulders)
        #expect(analysis.bodyFatEstimated)
        #expect((analysis.bodyFatPercent ?? 0) > 10 && (analysis.bodyFatPercent ?? 100) < 25)
        #expect(analysis.gaps.allSatisfy { !$0.finding.lowercased().contains("fat") })
    }

    @Test func tapeBodyFatUsesEachSexsSites() {
        let day = Day(year: 2026, month: 1, day: 1)
        let m = BodyMeasurements(day: day, neckCm: 33, waistCm: 84, naturalWaistCm: 72, glutesCm: 100)
        #expect(Physique.tapeBodyFat(m, sex: .female, heightCm: 165)
                == Physique.navyBodyFat(sex: .female, heightCm: 165, neckCm: 33, waistCm: 72, hipsCm: 100))
        #expect(Physique.tapeBodyFat(m, sex: .male, heightCm: 180)
                == Physique.navyBodyFat(sex: .male, heightCm: 180, neckCm: 33, waistCm: 84, hipsCm: nil))
        // Women's estimate needs the glutes; men's doesn't.
        #expect(Physique.tapeBodyFat(BodyMeasurements(day: day, neckCm: 33, waistCm: 84), sex: .female, heightCm: 165) == nil)
    }

    @Test func ffmiComesFromTheBestBodyFatReading() {
        let m = BodyMeasurements(day: Day(year: 2026, month: 1, day: 1), weightKg: 80, bodyFatPercent: 15, neckCm: 39, waistCm: 84)
        // 80 kg at 15% and 1.80 m: 68 kg lean, an FFMI of 20.99, already at the reference height.
        let entered = Physique.analyse([m], sex: .male, heightCm: 180)
        #expect(entered.bodyFatSource == .entered)
        #expect(abs((entered.ffmi ?? 0) - 20.99) < 0.01)
        #expect(abs((entered.normalizedFFMI ?? 0) - (entered.ffmi ?? 1)) < 0.001)
        #expect(entered.ffmiBand == .lotsOfRoom)
        // A recent Health reading beats a typed one: 72 kg lean is 22.2.
        let health = Physique.analyse([m], sex: .male, heightCm: 180, measuredBodyFat: 10)
        #expect(health.bodyFatSource == .health && health.bodyFatPercent == 10)
        #expect(health.ffmiBand == .someRoom)
        var untyped = m
        untyped.bodyFatPercent = nil
        #expect(Physique.analyse([untyped], sex: .male, heightCm: 180).bodyFatSource == .tape)
        // Shorter people are adjusted up to the reference height.
        let short = Physique.analyse([m], sex: .male, heightCm: 170)
        #expect((short.normalizedFFMI ?? 0) > (short.ffmi ?? 0))
    }

    @Test func limbSizesUseTheBiggerSide() {
        let day = Day(year: 2026, month: 1, day: 1)
        let m = BodyMeasurements(day: day, armCm: 30, armLeftCm: 35, armRightCm: 37)
        #expect(m.size(.arm) == 37)
        #expect(BodyMeasurements(day: day, armCm: 30).size(.arm) == 30)
        #expect(m.sides(.thigh) == nil)
    }

    @Test func aWaistDrivenRatioAsksForFatLossNotVolume() {
        let day = Day(year: 2026, month: 1, day: 1)
        // Shoulders 124 over a waist of 88 is 1.41; at a lean 82.8 cm waist it's about 1.48, on target.
        let soft = Physique.analyse([BodyMeasurements(day: day, neckCm: 39, shouldersCm: 124, waistCm: 88)], sex: .male, heightCm: 180)
        let reading = soft.proportions.first { $0.rule == .shoulderToWaist }
        #expect(reading?.flagged == true && reading?.cause == .fat)
        #expect(soft.gaps.isEmpty)
        #expect(soft.direction.fatLoss > 0 && soft.direction.build == 0)
        // Already lean with the same ratio: training closes it.
        let lean = Physique.analyse([BodyMeasurements(day: day, neckCm: 39, shouldersCm: 112, waistCm: 80)], sex: .male, heightCm: 180)
        #expect(lean.proportions.first { $0.rule == .shoulderToWaist }?.cause == .build)
        #expect(lean.gaps.first?.region == .shoulders)
        #expect(lean.direction.build > 0 && lean.direction.buildRegions == [.shoulders] && lean.direction.fatLoss == 0)
    }

    @Test func nothingAsksForFatLossAtTheFloor() {
        let day = Day(year: 2026, month: 1, day: 1)
        // The waist-driven body from above, but measured at 9% body fat: the waist isn't fat.
        let m = BodyMeasurements(day: day, bodyFatPercent: 9, neckCm: 39, shouldersCm: 124, waistCm: 88)
        let analysis = Physique.analyse([m], sex: .male, heightCm: 180)
        #expect(analysis.direction.atLeanFloor)
        #expect(analysis.direction.fatLoss == 0)
        #expect(analysis.proportions.first { $0.rule == .shoulderToWaist }?.cause == .build)
        #expect(Proportions.atLeanFloor(bodyFatPercent: 20, waistToHeight: nil, sex: .female))
        #expect(!Proportions.atLeanFloor(bodyFatPercent: 21, waistToHeight: nil, sex: .female))
        #expect(Proportions.atLeanFloor(bodyFatPercent: nil, waistToHeight: 0.42, sex: .male))
    }

    @Test func hourglassTellsWaistFromGlutes() {
        let day = Day(year: 2026, month: 1, day: 1)
        // Waist 76 over glutes 98 is 0.78; at a lean waist the glutes shrink half as fast and it's about 0.75.
        let soft = Physique.analyse([BodyMeasurements(day: day, shouldersCm: 100, waistCm: 82, naturalWaistCm: 76, glutesCm: 98)],
                                    sex: .female, heightCm: 165)
        #expect(soft.targets == .hourglass)
        #expect(soft.proportions.first { $0.rule == .waistToGlutes }?.cause == .fat)
        // Lean, with the glutes behind: build them.
        let lean = Physique.analyse([BodyMeasurements(day: day, shouldersCm: 94, waistCm: 74, naturalWaistCm: 70, glutesCm: 88)],
                                    sex: .female, heightCm: 165)
        #expect(lean.proportions.first { $0.rule == .waistToGlutes }?.cause == .build)
        #expect(lean.gaps.contains { $0.region == .glutes })
    }

    @Test func eachTargetSetChecksItsOwnRules() {
        #expect(ProportionTargets.standard(for: .male) == .vTaper)
        #expect(ProportionTargets.standard(for: .female) == .hourglass)
        #expect(ProportionTargets.standard(for: .unspecified) == .leannessOnly)
        #expect(ProportionTargets.vTaper.rules(sex: .male).contains(.chestToWaist))
        #expect(!ProportionTargets.vTaper.rules(sex: .female).contains(.chestToWaist))
        #expect(ProportionTargets.leannessOnly.rules(sex: .male) == [.thighToCalf])
        #expect(ProportionTargets.off.rules(sex: .female).isEmpty)
        let m = BodyMeasurements(day: Day(year: 2026, month: 1, day: 1), neckCm: 39, shouldersCm: 112, waistCm: 80)
        #expect(Physique.analyse([m], sex: .male, heightCm: 180, targets: .off).gaps.isEmpty)
        // A health ratio only ever asks for fat loss.
        let wide = Physique.analyse([BodyMeasurements(day: Day(year: 2026, month: 1, day: 1), waistCm: 100, glutesCm: 105)],
                                    sex: .male, heightCm: 180)
        let health = wide.proportions.first { $0.rule == .waistToHips }
        #expect(health?.cause == .fat && health?.region == nil)
    }

    @Test func aSideCountsAsLaggingOnlyWhenItLasts() {
        let start = Day(year: 2026, month: 1, day: 1)
        func check(_ offset: Int, _ left: Double, _ right: Double) -> BodyMeasurements {
            BodyMeasurements(day: start.adding(days: offset), armLeftCm: left, armRightCm: right)
        }
        // One reading apart is noise, and so are two within a fortnight.
        #expect(Physique.asymmetries([check(0, 35, 37)]).isEmpty)
        #expect(Physique.asymmetries([check(0, 35, 37), check(7, 35.1, 37)]).isEmpty)
        // Apart at two check-ins two weeks apart: the left arm lags.
        let lagging = Physique.asymmetries([check(0, 35, 37), check(14, 35.2, 37.1)])
        #expect(lagging.first?.limb == .arm && lagging.first?.smaller == .left)
        #expect(lagging.first.map { $0.magnitude > 0 && $0.magnitude < 1 } == true)
        // Once flagged it holds while the sides are more than a centimetre apart, and clears inside one.
        #expect(Physique.asymmetries([check(0, 35, 37), check(14, 35.2, 37.1), check(28, 35.9, 37.1)]).count == 1)
        #expect(Physique.asymmetries([check(0, 35, 37), check(14, 35.2, 37.1), check(42, 36.6, 37.1)]).isEmpty)
        // A centimetre either way is normal.
        #expect(Physique.asymmetries([check(0, 36, 37), check(14, 36, 37)]).isEmpty)
        // Readings with no side never count.
        #expect(Physique.asymmetries([BodyMeasurements(day: start, armCm: 35), BodyMeasurements(day: start.adding(days: 20), armCm: 35)]).isEmpty)
    }

    @Test func restKeepsMinimumsForHeavyCompounds() {
        let heavy = Rest.plan(role: .heavyCompound, reps: 5, defaultSeconds: 180, enduranceScore: 70, hrGuidance: true)
        #expect(!heavy.heartRateGuided && heavy.minimum >= 150)
        let accessory = Rest.plan(role: .accessory, reps: 12, defaultSeconds: 75, enduranceScore: 30, hrGuidance: true)
        #expect(accessory.heartRateGuided && accessory.target > 75)
        let zones = HeartRateZones(resting: 60, maximum: 190)
        #expect(!Rest.recovered(heartRate: 100, preSet: 95, zones: zones, elapsed: 30, plan: accessory))
        #expect(Rest.recovered(heartRate: 105, preSet: 95, zones: zones, elapsed: 50, plan: accessory))
        #expect(!Rest.recovered(heartRate: 150, preSet: 95, zones: zones, elapsed: 80, plan: accessory))
    }

    @Test func heartRateRecoveryDrop() {
        let end = Date()
        let samples: [(date: Date, bpm: Double)] = [(end, 150), (end.addingTimeInterval(30), 130), (end.addingTimeInterval(60), 112)]
        let result = HeartRateRecovery.drop(samples: samples, setEnd: end)
        #expect(result?.peak == 150 && result?.drop == 38)
    }

    @Test func benchmarkImprovementDirection() {
        #expect(EnduranceBenchmark.row2k.improvement(from: 480, to: 470) > 0)
        #expect(EnduranceBenchmark.bike12min.improvement(from: 6000, to: 6200) > 0)
    }
}

@Suite("Quests and trajectories")
struct HubTests {
    @Test func questsAreCappedAndSpread() {
        let day = Day(year: 2026, month: 1, day: 1)
        let quests = [
            Quest(id: "a", title: "A", stat: .agility, source: .liftTrack, day: day, priority: 5),
            Quest(id: "b", title: "B", stat: .agility, source: .liftTrack, day: day, priority: 4),
            Quest(id: "c", title: "C", stat: .endurance, source: .liftTrack, day: day, priority: 3),
            Quest(id: "d", title: "D", stat: .vitality, source: .macroTrack, day: day, priority: 2),
            Quest(id: "e", title: "E", stat: .strength, source: .liftTrack, day: day, priority: 1),
        ]
        #expect(Quests.forDay(day, from: quests).map(\.id) == ["a", "c", "d"])
    }

    @Test func trajectoryReadsTheTrend() {
        let start = Day(year: 2026, month: 1, day: 1)
        let goal = TargetGoal(stat: .strength, title: "Bench 100", metric: "category:horizontalPress", target: 100, start: start,
                              deadline: start.adding(days: 120))
        let onPace = (0..<6).map { (start.adding(days: $0 * 7), 80 + Double($0) * 1.3) }
        #expect(Trajectories.assess(onPace, goal: goal, today: start.adding(days: 35)) == .onPace)
        let flat = (0..<6).map { (start.adding(days: $0 * 7), 80.0) }
        #expect(Trajectories.assess(flat, goal: goal, today: start.adding(days: 35)) == .stalled)
        let down = (0..<6).map { (start.adding(days: $0 * 7), 85 - Double($0) * 1.5) }
        #expect(Trajectories.assess(down, goal: goal, today: start.adding(days: 35)) == .regressing)
    }
}
