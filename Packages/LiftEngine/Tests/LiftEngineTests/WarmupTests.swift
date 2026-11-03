import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// Warm-ups the way they're done at the gym: a bar lift from the empty bar to a few reps at the
/// working weight, a leg press a plate a side at a time, a curl tried once at its weight.
@Suite("Warm-ups")
struct WarmupTests {
    static let kg = Gym.preset(.fullGym, unit: .kg)
    static let lb = Gym.preset(.fullGym, unit: .lb)

    /// The warm-ups before work at `load` in the gym's unit, aiming for two in reserve.
    func warmups(
        _ id: String, _ load: Double, reps: Int, role: SlotRole = .main, gym: Gym = WarmupTests.kg, findingWeight: Bool = false
    ) -> [SetPrescription] {
        let exercise = Fixture.catalog.resolve(id)
        return Warmup.sets(
            to: gym.unit.toKilograms(load), reps: reps, targetRIR: 2, exercise: exercise, role: role,
            increments: gym.increments(for: exercise.equipment), findingWeight: findingWeight)
    }

    /// Each set's load in the gym's unit, to two places.
    func loads(_ sets: [SetPrescription], in unit: WeightUnit = .kg) -> [Double] {
        sets.map { (unit.fromKilograms($0.loadKg ?? -1) * 100).rounded() / 100 }
    }

    @Test("a bar lift starts with the empty bar and ends with a few reps at the working weight")
    func barLifts() {
        // 140 kg squats for 5: the bar, three even jumps, then 140 for 3.
        let squat = warmups("barbell-back-squat", 140, reps: 5)
        #expect(loads(squat) == [20, 50, 80, 110, 140])
        #expect(squat.map(\.targetReps) == [5, 5, 5, 3, 3])
        #expect(squat.allSatisfy { $0.kind == .warmup })
        #expect(squat.last?.targetRIR == 4, "three of five at the working weight leaves the work's two and two more")
        // 80 kg bench for 8: one jump is enough, and 4 at the working weight.
        let bench = warmups("barbell-bench-press", 80, reps: 8)
        #expect(loads(bench) == [20, 50, 80])
        #expect(bench.map(\.targetReps) == [8, 5, 4])
        // A light press goes straight from the bar to the working weight.
        #expect(loads(warmups("barbell-overhead-press", 50, reps: 6)) == [20, 50])
        // Work with the bar alone: tried once with it.
        let empty = warmups("barbell-overhead-press", 20, reps: 8)
        #expect(loads(empty) == [20] && empty.map(\.targetReps) == [4])
        // A trap bar starts with its own bar, and an accessory on a bar warms up the same way.
        #expect(loads(warmups("trap-bar-deadlift", 140, reps: 5)).first == 25)
        #expect(loads(warmups("barbell-row", 70, reps: 10, role: .accessory)) == [20, 45, 70])
    }

    @Test("in pounds the jumps land on plates: a 405 deadlift warms up at 45, 135, 225 and 315")
    func pounds() {
        let deadlift = warmups("conventional-deadlift", 405, reps: 5, gym: Self.lb)
        #expect(loads(deadlift, in: .lb) == [45, 135, 225, 315, 405])
        #expect(deadlift.map(\.targetReps) == [5, 5, 5, 3, 3])
        #expect(loads(warmups("barbell-bench-press", 225, reps: 5, gym: Self.lb), in: .lb) == [45, 105, 165, 225])
    }

    @Test("a plate-loaded lift takes a plate a side more each set up to the work, four sets at most")
    func plateLoaded() {
        // A 360 lb leg press for 10: one, two and three 45s a side, then the work.
        let press = warmups("leg-press", 360, reps: 10, role: .accessory, gym: Self.lb)
        #expect(loads(press, in: .lb) == [90, 180, 270])
        #expect(press.map(\.targetReps) == [8, 8, 5])
        // Eight 25s a side: four sets, spread out and ending a plate short.
        let heavy = warmups("leg-press", 400, reps: 10, role: .accessory)
        #expect(loads(heavy) == [100, 200, 300, 350])
        #expect(heavy.map(\.targetReps) == [8, 8, 5, 3])
        // Under two of the biggest plates, the biggest that fits; a Smith machine climbs by plates too.
        #expect(loads(warmups("leg-press", 40, reps: 10, role: .accessory)) == [30])
        #expect(loads(warmups("hack-squat", 100, reps: 8, role: .accessory)) == [50])
        #expect(loads(warmups("smith-squat", 100, reps: 8)) == [50])
        // Less than the smallest pair: tried once at the weight.
        #expect(loads(warmups("leg-press", 2, reps: 10, role: .accessory)) == [2])
        #expect(press.allSatisfy { $0.kind == .warmup })
    }

    @Test("a curl, and an accessory on dumbbells, cables or a machine, is tried once at its weight for 2 to 4 reps")
    func tried() {
        let accessories: [(String, Double, Int)] = [
            ("cable-curl", 30, 12), ("db-curl", 14, 10), ("barbell-curl", 30, 10), ("lat-pulldown", 60, 10),
            ("db-bench-press", 30, 8), ("machine-chest-press", 70, 10), ("leg-extension", 50, 15),
        ]
        for (id, load, reps) in accessories {
            let sets = warmups(id, load, reps: reps, role: .accessory)
            #expect(loads(sets) == [load], "\(id)")
            #expect(sets.map(\.targetReps) == [4] && sets.allSatisfy { $0.kind == .warmup }, "\(id)")
        }
        // Half the work's reps, between two and four.
        #expect(warmups("cable-curl", 30, reps: 5, role: .accessory).map(\.targetReps) == [3])
        #expect(warmups("cable-curl", 30, reps: 3, role: .accessory).map(\.targetReps) == [2])
        // An isolation lift leading a day is still only tried.
        #expect(warmups("cable-curl", 30, reps: 12).count == 1)
    }

    @Test("dumbbell, cable and machine lifts that lead a day climb at about half and three quarters")
    func leadingLifts() {
        let bench = warmups("db-bench-press", 30, reps: 8)
        #expect(loads(bench) == [14, 22])
        #expect(bench.map(\.targetReps) == [8, 5])
        #expect(loads(warmups("machine-chest-press", 100, reps: 8)) == [45, 65, 80])
    }

    @Test("bodyweight, timed work and drills warm up by doing")
    func none() {
        #expect(warmups("pull-up", 10, reps: 6).isEmpty)
        #expect(warmups("farmers-carry", 30, reps: 1).isEmpty)
        #expect(warmups("barbell-back-squat", 100, reps: 5, role: .mobility).isEmpty)
        #expect(warmups("barbell-back-squat", 0, reps: 5).isEmpty)
        // A slipped load warms up nothing rather than climbing for ever.
        #expect(warmups("leg-press", 82_500_000, reps: 10, role: .accessory).isEmpty)
        #expect(warmups("leg-press", .infinity, reps: 10, role: .accessory).isEmpty)
    }

    @Test("still finding the weight: the lifts that climb climb toward the guess, the rest go straight to finding it")
    func findingWeight() {
        #expect(warmups("cable-curl", 30, reps: 10, role: .accessory, findingWeight: true).isEmpty)
        #expect(warmups("lat-pulldown", 60, reps: 10, role: .accessory, findingWeight: true).isEmpty)
        #expect(loads(warmups("leg-press", 360, reps: 10, role: .accessory, gym: Self.lb, findingWeight: true), in: .lb) == [90, 180, 270])
        #expect(loads(warmups("barbell-back-squat", 80, reps: 8, findingWeight: true)) == [20, 50, 80])
        #expect(warmups("leg-press", 2, reps: 10, role: .accessory, findingWeight: true).isEmpty)
    }

    @Test func styles() {
        let style = { (id: String, role: SlotRole) in Warmup.style(for: Fixture.catalog.resolve(id), role: role) }
        #expect(style("barbell-back-squat", .main) == .bar && style("barbell-row", .accessory) == .bar)
        #expect(style("leg-press", .accessory) == .plates && style("smith-squat", .main) == .plates)
        #expect(style("db-bench-press", .main) == .ramp && style("db-bench-press", .accessory) == .test)
        #expect(style("barbell-curl", .accessory) == .test && style("db-curl", .main) == .test)
        #expect(style("pull-up", .main) == .none && style("farmers-carry", .accessory) == .none)
    }
}
