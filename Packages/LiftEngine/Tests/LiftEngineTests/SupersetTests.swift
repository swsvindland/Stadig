import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// A short session's two compounds done in turn: warm-ups first and on their own, then the work
/// sets paired; and split up when the gym's too busy to hold two stations.
@Suite("Supersets")
struct SupersetTests {
    static let start = Fixture.start.date().addingTimeInterval(18 * 3600)
    static let environment = SessionEnvironment(
        catalog: Fixture.catalog, gym: Gym.preset(.fullGym, unit: .kg), trust: TrustState(prior: 0.5),
        phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: [:], enduranceScore: 50, heartRateGuidedRest: false)

    static func set(_ kind: SetKind, _ kg: Double, _ reps: Int) -> SetPrescription {
        SetPrescription(kind: kind, loadKg: kg, targetReps: reps, targetRIR: kind == .warmup ? 5 : 2)
    }

    /// Bench with three warm-ups before its three work sets, paired with a partner: pull-ups with no
    /// warm-up, or a cable row with one.
    func session(partnerWarmsUp: Bool = false) -> LiveSession {
        let warmups = [Self.set(.warmup, 20, 10), Self.set(.warmup, 50, 5), Self.set(.warmup, 70, 3)]
        let bench = PlannedItem(
            slotID: nil, block: .main, exerciseID: "barbell-bench-press", role: .main,
            sets: warmups + Array(repeating: Self.set(.working, 80, 6), count: 3),
            repRange: RepRange(5, 8), rest: RestPlan(target: 150, minimum: 90, heartRateGuided: false), supersetGroup: 1)
        let partner =
            partnerWarmsUp
            ? PlannedItem(
                slotID: nil, block: .main, exerciseID: "cable-row", role: .main,
                sets: [Self.set(.warmup, 30, 8)] + Array(repeating: Self.set(.working, 60, 10), count: 3),
                repRange: RepRange(8, 12), rest: RestPlan(target: 120, minimum: 60, heartRateGuided: false), supersetGroup: 1)
            : PlannedItem(
                slotID: nil, block: .main, exerciseID: "pull-up", role: .main, sets: Array(repeating: Self.set(.working, 0, 8), count: 3),
                repRange: RepRange(6, 10), rest: RestPlan(target: 120, minimum: 60, heartRateGuided: false), supersetGroup: 1)
        let plan = SessionPlan(
            day: Fixture.start, title: "Full body A", mesocycleID: nil, dayID: nil, week: 1, deload: false, checkIn: false,
            assessment: false, minimumEffectiveDose: false, items: [bench, partner], notes: [], quests: [])
        return LiveSession(plan: plan, device: "Test", now: Self.start)
    }

    /// Does the sets as they come, a minute apart from the last one logged, up to `limit`, and names
    /// each: "bench warm-up", "bench", "pull-up", "row warm-up".
    func walk(_ live: inout LiveSession, limit: Int = 50) -> [String] {
        var order: [String] = []
        var now = live.items.flatMap(\.loggedSets).map(\.date).max() ?? Self.start
        while let current = live.current, order.count < limit {
            let set = live.items[current.item].sets[current.set]
            let name =
                switch live.items[current.item].exerciseID {
                case "barbell-bench-press": "bench"
                case "cable-row": "row"
                default: "pull-up"
                }
            let warmup = set.prescription.kind == .warmup
            order.append(warmup ? "\(name) warm-up" : name)
            now = now.addingTimeInterval(60)
            live.log(
                item: current.item, set: current.set, reps: set.prescription.targetReps, loadKg: set.prescription.loadKg,
                rating: warmup ? nil : .orange, environment: Self.environment, now: now)
        }
        return order
    }

    @Test("a superset's warm-ups run straight through, and only work sets alternate")
    func warmupsComeFirst() {
        var live = session()
        #expect(
            walk(&live) == [
                "bench warm-up", "bench warm-up", "bench warm-up", "bench", "pull-up", "bench", "pull-up", "bench", "pull-up",
            ])
        // A partner's own warm-ups come before the pairing too, after the first lift's.
        var withRow = session(partnerWarmsUp: true)
        #expect(
            walk(&withRow) == [
                "bench warm-up", "bench warm-up", "bench warm-up", "row warm-up", "bench", "row", "bench", "row", "bench", "row",
            ])
    }

    @Test("the last warm-up keeps its breather; the switch to a partner is quick between work sets and warm-ups")
    func restsInASuperset() {
        var live = session()
        _ = walk(&live, limit: 3)
        // Bench's last warm-up, with its first work set next: half the work's rest.
        #expect(live.rest?.plan.target == 75)
        _ = walk(&live, limit: 1)
        // A bench work set, then straight on to the pull-ups.
        #expect(live.rest?.plan.target == 20)
        #expect(live.current.map { live.items[$0.item].exerciseID } == "pull-up")

        var withRow = session(partnerWarmsUp: true)
        _ = walk(&withRow, limit: 3)
        // On to the row's warm-up: a quick switch.
        #expect(withRow.rest?.plan.target == 20)
        _ = walk(&withRow, limit: 1)
        // The row's last warm-up, with the bench's work next: the row's breather, half its rest.
        #expect(withRow.rest?.plan.target == 60)
        #expect(withRow.current.map { withRow.items[$0.item].exerciseID } == "barbell-bench-press")
    }

    @Test("a busy gym can split a superset: one exercise after the other, each with its own rest")
    func split() {
        var live = session()
        #expect(!live.canSplitSuperset(item: 5))
        #expect(live.canSplitSuperset(item: 0) && live.canSplitSuperset(item: 1))
        // Warmed up and the first bench set done: the 20-second switch to pull-ups is running.
        let done = walk(&live, limit: 4)
        let started = live.rest?.started
        #expect(live.rest?.plan.target == 20)
        live.splitSuperset(item: 1, now: Self.start.addingTimeInterval(270))
        #expect(live.items.allSatisfy { $0.plan.supersetGroup == nil })
        #expect(!live.canSplitSuperset(item: 0))
        // The switch becomes the bench's own rest, from the same set.
        #expect(live.rest?.plan.target == 150)
        #expect(live.rest?.started == started)
        #expect(live.rest.map { $0.endsAt.timeIntervalSince($0.started) } == 150)
        #expect(live.undoableSet == nil, "undo would put back half the pair")
        // The bench carries on to the end, then the pull-ups.
        #expect(walk(&live) == ["bench", "bench", "pull-up", "pull-up", "pull-up"])
        #expect(done.count == 4)
        // Pull-ups rest their own rest between sets now.
        var again = session()
        again.splitSuperset(item: 0, now: Self.start)
        _ = walk(&again, limit: 7)
        #expect(again.current.map { again.items[$0.item].exerciseID } == "pull-up")
        #expect(again.rest?.plan.target == 120)
    }
}

/// A machine that moves by its own amount: a leg press in 20s, a cable stack with finer plates.
@Suite("Exercises' own steps")
struct ExerciseStepTests {
    let gym = Gym.preset(.fullGym, unit: .lb)
    let legPress = Fixture.catalog.resolve("leg-press")

    func lb(_ kg: Double) -> Double { (WeightUnit.lb.fromKilograms(kg) * 100).rounded() / 100 }
    func kg(_ lb: Double) -> Double { WeightUnit.lb.toKilograms(lb) }

    @Test("an exercise's own step replaces its equipment's, for that exercise only")
    func ownStep() {
        // A plate-loaded sled moves by a pair of the smallest plates.
        #expect(gym.increments(for: legPress).usualStep == 5)
        #expect(lb(gym.increments(for: legPress).step(kg(180), direction: 1)) == 185)
        let twenties = gym.setting(step: 20, for: legPress)
        let steps = twenties.increments(for: legPress)
        #expect(steps.exerciseStep == 20)
        #expect(lb(steps.step(kg(180), direction: 1)) == 200)
        #expect(lb(steps.step(kg(180), direction: -1)) == 160)
        #expect(lb(steps.round(kg(190), down: true)) == 180)
        // From a load typed between the steps, onto them.
        #expect(lb(steps.step(kg(185), direction: 1)) == 200)
        #expect(lb(steps.step(kg(185), direction: -1)) == 180)
        // Other plate-loaded lifts keep the plates.
        let chest = Fixture.catalog.resolve("plate-loaded-chest-press")
        #expect(twenties.increments(for: chest).exerciseStep == nil)
        #expect(lb(twenties.increments(for: chest).step(kg(180), direction: 1)) == 185)
        // A stack finer than the gym's 10s.
        let row = Fixture.catalog.resolve("cable-row")
        let fives = gym.setting(step: 5, for: row).increments(for: row)
        #expect(lb(fives.step(kg(80), direction: 1)) == 85)
    }

    @Test("a bar's steps are its plates, and a step the same as the gym's isn't kept")
    func whatTakesAStep() {
        let bench = Fixture.catalog.resolve("barbell-bench-press")
        #expect(!GymIncrements.takesOwnStep(bench))
        #expect(gym.setting(step: 20, for: bench).exerciseSteps.isEmpty)
        #expect(gym.setting(step: 5, for: legPress).exerciseSteps.isEmpty)
        #expect(gym.setting(step: 20, for: legPress).setting(step: nil, for: legPress).exerciseSteps.isEmpty)
        // Pull-ups with a belt can: the plates on it.
        #expect(GymIncrements.takesOwnStep(Fixture.catalog.resolve("pull-up")))
    }

    @Test("the progression plans on an exercise's own step")
    func progressionUsesTheStep() {
        let twenties = gym.setting(step: 20, for: legPress)
        // Last time 300 × 12, just right, the top of an 8–12 range. 20 lb on 300 is too coarse to
        // progress by load, so the reps climb the range and then the weight goes up a step.
        let history = (0..<3).map { index in
            LoggedSet(
                exerciseID: legPress.id, date: SupersetTests.start.addingTimeInterval(Double(index) * 120), loadKg: kg(300), reps: 12,
                rating: .orange, restBeforeSeconds: index == 0 ? nil : 120)
        }
        let context = ProgressionContext(
            exercise: legPress, increments: twenties.increments(for: legPress), trust: TrustState(prior: 0.6),
            phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: history)
        let next = Progression.prescribe(SlotTarget(sets: 3, repRange: RepRange(8, 12), targetRIR: 2), context)
        // The top of the range: the next 20 up, the reps from the bottom.
        #expect(next.mode == .reps)
        #expect(next.sets.allSatisfy { lb($0.loadKg ?? 0) == 320 && $0.targetReps == 8 })
    }

    @Test("a gym saved before exercises had their own steps reads as having none")
    func olderGymsDecode() throws {
        let encoded = try JSONEncoder().encode(gym.setting(step: 20, for: legPress))
        var json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["exerciseSteps"] != nil)
        json["exerciseSteps"] = nil
        let older = try JSONDecoder().decode(Gym.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(older.exerciseSteps.isEmpty)
        #expect(older.machineStep == gym.machineStep)
        let round = try JSONDecoder().decode(Gym.self, from: encoded)
        #expect(round.exerciseSteps == [legPress.id: 20])
    }

    @Test("edits merge exercise by exercise; a change of unit takes them all")
    func editsMerge() {
        let row = Fixture.catalog.resolve("cable-row")
        let original = gym.setting(step: 20, for: legPress)
        // Meanwhile, on another device: the row's stack in 5s.
        let latest = original.setting(step: 5, for: row)
        // Here: the dumbbells go heavier, and the leg press back to the plates.
        var edited = original.setting(step: nil, for: legPress)
        edited.dumbbellMax = 150
        let saved = latest.applying(edited, from: original)
        #expect(saved.exerciseSteps == [row.id: 5])
        #expect(saved.dumbbellMax == 150)
        // Kilograms: no step of 20 lb survives, and none of the plates do either.
        #expect(latest.applying(original.converted(to: .kg), from: original).exerciseSteps.isEmpty)
        // Another kind of gym is still this gym, with its machines' steps.
        #expect(original.switched(to: .homeGym).exerciseSteps == [legPress.id: 20])
    }
}
