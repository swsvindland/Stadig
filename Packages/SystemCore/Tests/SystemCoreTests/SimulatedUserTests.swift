import Foundation
import Testing

@testable import SystemCore

/// The progression, fatigue and trust logic is the product. These run simulated people through
/// many weeks with the real code and check the system ends up believing the right things.
@Suite("Simulated users")
struct SimulatedUserTests {
    static let slots = [
        TrainingSimulation.Slot(exercise: .chestPress, increments: FixedIncrements(stepKg: 5), sets: 3, repRange: RepRange(8, 12)),
        TrainingSimulation.Slot(exercise: .bench, increments: FixedIncrements(stepKg: 2.5), sets: 3, repRange: RepRange(5, 8)),
        TrainingSimulation.Slot(exercise: .legExtension, increments: FixedIncrements(stepKg: 5), sets: 3, repRange: RepRange(10, 15)),
    ]

    @Test("An honest novice earns trust and the estimates track reality")
    func honestNovice() {
        var sim = TrainingSimulation(lifter: .honestNovice, slots: Self.slots)
        sim.run(weeks: 12)
        let lifter = SimulatedLifter.honestNovice
        #expect(sim.trust.score > lifter.experience.startingTrust + 0.2, "trust \(sim.trust.score)")
        #expect(abs(sim.trust.bias) < 1)
        for exercise in [TestExercise.chestPress, .bench] {
            let truth = lifter.trueE1RM(exercise.id, week: 12)
            let estimate = sim.estimate(exercise) ?? 0
            #expect(abs(estimate / truth - 1) < 0.12, "\(exercise.name): estimate \(estimate) vs true \(truth)")
            #expect((sim.lastWorkingLoad(exercise) ?? 0) > (sim.firstWorkingLoad(exercise) ?? .infinity), "\(exercise.name) loads should rise")
        }
    }

    @Test("A sandbagger is caught early, and objective tests still find their real strength")
    func sandbagger() {
        var sim = TrainingSimulation(lifter: .sandbagger, slots: Self.slots)
        var honest = TrainingSimulation(lifter: .honestNovice, slots: Self.slots)
        sim.run(weeks: 1)
        honest.run(weeks: 1)
        // The first rep-outs expose the sandbagging.
        #expect(sim.trust.bias > 0.8, "bias \(sim.trust.bias)")
        #expect(sim.trust.score < honest.trust.score, "sandbagger \(sim.trust.score) vs honest \(honest.trust.score)")
        // Low trust means verification pushes.
        #expect(sim.adjustments.contains(.verify))

        sim.run(weeks: 11, from: 1)
        honest.run(weeks: 11, from: 1)
        #expect(sim.trust.score < honest.trust.score)
        #expect(sim.trust.bias > 0)
        let lifter = SimulatedLifter.sandbagger
        // Machine rep-outs pin the estimates despite the ratings.
        for exercise in [TestExercise.chestPress, .legExtension] {
            let truth = lifter.trueE1RM(exercise.id, week: 12)
            let estimate = sim.estimate(exercise) ?? 0
            #expect(abs(estimate / truth - 1) < 0.1, "\(exercise.name): estimate \(estimate) vs true \(truth)")
        }
        // Free weights for a low-trust novice get no failure tests, only controlled pushes, so the
        // estimate stays conservative but in range.
        let truth = lifter.trueE1RM(TestExercise.bench.id, week: 12)
        let bench = sim.estimate(.bench) ?? 0
        #expect(bench / truth > 0.8 && bench < truth, "bench estimate \(bench) vs true \(truth)")
    }

    @Test("An overconfident veteran loses trust and gets conservative estimates")
    func overconfident() {
        var sim = TrainingSimulation(lifter: .overconfident, slots: Self.slots)
        sim.run(weeks: 10)
        let lifter = SimulatedLifter.overconfident
        #expect(sim.trust.score < lifter.experience.startingTrust - 0.1, "trust \(sim.trust.score)")
        #expect(sim.trust.bias < -0.5, "bias \(sim.trust.bias)")
        let truth = lifter.trueE1RM(TestExercise.bench.id, week: 10)
        let estimate = sim.estimate(.bench) ?? 0
        #expect(estimate < truth * 1.08, "estimate \(estimate) shouldn't run ahead of true \(truth)")
    }

    @Test("A plateaued veteran's stall is found, and read by phase")
    func plateaued() {
        var sim = TrainingSimulation(lifter: .plateaued, slots: [Self.slots[1]])
        sim.assessmentWeeks = 2
        sim.run(weeks: 9)
        let today = sim.startDate.adding(weeks: 9)
        let context = ProgressionContext(
            exercise: TestExercise.bench, increments: FixedIncrements(stepKg: 2.5), trust: sim.trust,
            phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80,
            history: sim.history[TestExercise.bench.id] ?? [])
        let maintenance = Stalls.detect(
            context, sets: 3, repRange: RepRange(5, 8), today: today,
            phase: NutritionPhase.assumedMaintenance.effects, beatUp: false)
        #expect(maintenance?.reading == .programming, "\(String(describing: maintenance))")
        #expect((maintenance?.weeks ?? 0) >= 3)
        #expect(maintenance?.suggestion?.loadKg != nil)
        let cut = Stalls.detect(
            context, sets: 3, repRange: RepRange(5, 8), today: today,
            phase: NutritionPhase(kind: .cut, source: .macroTrack).effects, beatUp: false)
        #expect(cut?.reading == .expectedInDeficit)
        let beatUp = Stalls.detect(
            context, sets: 3, repRange: RepRange(5, 8), today: today,
            phase: NutritionPhase.assumedMaintenance.effects, beatUp: true)
        #expect(beatUp?.reading == .recovery)
    }

    @Test("A growing lifter is not reported as stalled")
    func noFalseStall() {
        var sim = TrainingSimulation(lifter: .honestNovice, slots: [Self.slots[1]])
        sim.run(weeks: 9)
        let context = ProgressionContext(
            exercise: TestExercise.bench, increments: FixedIncrements(stepKg: 2.5), trust: sim.trust,
            phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80,
            history: sim.history[TestExercise.bench.id] ?? [])
        let stall = Stalls.detect(
            context, sets: 3, repRange: RepRange(5, 8), today: sim.startDate.adding(weeks: 9),
            phase: NutritionPhase.assumedMaintenance.effects, beatUp: false)
        #expect(stall == nil, "\(String(describing: stall))")
    }

    @Test("Reps that fall set to set at the same weight are fatigue, not misses or overconfidence")
    func fallingRepsStillProgress() {
        // The leg extension's 10 kg steps are coarse at its weight, so it climbs reps instead.
        let slots = [
            Self.slots[0], Self.slots[1],
            TrainingSimulation.Slot(exercise: .legExtension, increments: FixedIncrements(stepKg: 10), sets: 3, repRange: RepRange(10, 15)),
        ]
        var sim = TrainingSimulation(lifter: .realFatigue, slots: slots)
        sim.run(weeks: 12)
        let lifter = SimulatedLifter.realFatigue
        // Holding the weight with every set the same reps made about a third of all sets misses,
        // and read this honest lifter as overconfident (bias −0.7, trust barely above where it started).
        let sets = slots.flatMap { sim.history[$0.exercise.id] ?? [] }
        let misses = sets.filter { $0.rating == .red }.count
        #expect(Double(misses) < Double(sets.count) * 0.25, "\(misses) misses in \(sets.count) sets")
        #expect(sim.trust.score > lifter.experience.startingTrust + 0.15, "trust \(sim.trust.score)")
        #expect(abs(sim.trust.bias) < 0.5, "bias \(sim.trust.bias)")
        for slot in slots {
            let truth = lifter.trueE1RM(slot.exercise.id, week: 12)
            let estimate = sim.estimate(slot.exercise) ?? 0
            #expect(abs(estimate / truth - 1) < 0.12, "\(slot.exercise.name): estimate \(estimate) vs true \(truth)")
        }
        // Fine steps raise the weight; the coarse leg extension raises the weight or the reps.
        for exercise in [TestExercise.chestPress, .bench] {
            #expect((sim.lastWorkingLoad(exercise) ?? 0) > (sim.firstWorkingLoad(exercise) ?? .infinity), "\(exercise.name) loads should rise")
        }
        let legs = (sim.history[TestExercise.legExtension.id] ?? []).filter { $0.kind == .working }
        let early = legs.prefix(6).map { OneRepMax.epley($0.loadKg, reps: $0.reps) }.max() ?? 0
        let late = legs.suffix(6).map { OneRepMax.epley($0.loadKg, reps: $0.reps) }.max() ?? 0
        #expect(late > early * 1.05, "leg extension \(early) → \(late)")
    }

    @Test("Free-weight rep-outs are only offered to lifters who've earned them")
    func failureTiers() {
        let novice = TrustState(experience: .novice)
        #expect(FailurePolicy.allowsRepOut(TestExercise.chestPress, trust: novice, experience: .novice, hasSafeties: false))
        #expect(!FailurePolicy.allowsRepOut(TestExercise.bench, trust: novice, experience: .novice, hasSafeties: true))
        #expect(
            FailurePolicy.allowsRepOut(TestExercise.bench, trust: TrustState(experience: .experienced), experience: .experienced, hasSafeties: true))
        #expect(
            !FailurePolicy.allowsRepOut(TestExercise.bench, trust: TrustState(experience: .experienced), experience: .experienced, hasSafeties: false)
        )
        // Deadlifts can fail safely without pins, but low-trust lifters stop at form breakdown.
        #expect(
            FailurePolicy.allowsRepOut(
                TestExercise.deadlift, trust: TrustState(experience: .experienced), experience: .experienced, hasSafeties: false))
        #expect(FailurePolicy.stopAtFormBreakdown(TestExercise.deadlift, trust: TrustState(experience: .experienced)))
        #expect(!FailurePolicy.stopAtFormBreakdown(TestExercise.chestPress, trust: novice))
    }
}
