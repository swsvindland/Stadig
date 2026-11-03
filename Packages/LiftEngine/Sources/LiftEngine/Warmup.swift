import ExerciseLibrary
import Foundation
import SystemCore

/// The sets before an exercise's work, the way people warm up at the gym. A lift on a bar starts
/// with the empty bar and ends with a few reps at the working weight; a plate-loaded machine (a leg
/// press, a hack squat) takes a plate a side more each set up to the work; isolation work, and the
/// accessories on dumbbells, cables and machines, get one short set at the working weight to see
/// that it feels right. Warm-ups are never rated and never count as work.
public enum Warmup {
    /// How an exercise warms up.
    public enum Style: Sendable, Equatable {
        /// The empty bar, a jump or two, then the working weight for a few reps.
        case bar
        /// A plate a side more each set, up to the work.
        case plates
        /// About half and three quarters of the work: the dumbbell, cable and machine lifts that lead a day.
        case ramp
        /// A few reps at the working weight, to try it.
        case test
        /// Bodyweight, assisted and timed work, which warm up by doing, and anything that isn't lifting.
        case none
    }

    /// How an exercise warms up in a slot: only lifts with a weight to find their way to.
    public static func style(for exercise: Exercise, role: SlotRole) -> Style {
        let loaded = exercise.loadBasis == .external || exercise.loadBasis == .perHand
        guard role == .main || role == .accessory, loaded, !exercise.timed else { return .none }
        // A barbell curl is tried at its weight like any curl: the bar alone warms nothing up.
        guard exercise.isCompound else { return .test }
        switch exercise.equipment {
        case .barbell, .ezBar, .trapBar: return .bar
        // A Smith machine's bar isn't counted in its loads, so it climbs by plates like a sled.
        case .plateLoaded, .smith: return .plates
        default: return role == .main ? .ramp : .test
        }
    }

    /// The warm-up sets before work at `workingKg` (per hand for dumbbells) for `reps`, lightest
    /// first, on loads the gym makes. With `findingWeight` the working weight is only a guess: the
    /// lifts that climb still climb toward it, but there's nothing to try yet, so the rest get none
    /// (the first set finding the weight is the try).
    public static func sets(
        to workingKg: Double, reps: Int, targetRIR: Double, exercise: Exercise, role: SlotRole, increments: GymIncrements,
        findingWeight: Bool = false
    ) -> [SetPrescription] {
        // Past the most anyone lifts is a slipped digit (or infinity) and would climb for ever.
        guard workingKg > 0, workingKg <= GymIncrements.maximumLoadKg, reps > 0 else { return [] }
        let tried: [SetPrescription] = findingWeight ? [] : [test(at: workingKg, reps: reps, targetRIR: targetRIR)]
        switch style(for: exercise, role: role) {
        case .bar: return barRamp(to: workingKg, reps: reps, targetRIR: targetRIR, increments: increments)
        case .plates: return plateRamp(to: workingKg, reps: reps, increments: increments) ?? tried
        case .ramp: return ramp(to: workingKg, reps: reps, increments: increments)
        case .test: return tried
        case .none: return []
        }
    }

    /// The empty bar, then up to three even jumps of about 30 kg at most, then the working weight
    /// for a few reps. Work with the bar alone is tried once with it.
    static func barRamp(to workingKg: Double, reps: Int, targetRIR: Double, increments: GymIncrements) -> [SetPrescription] {
        let bar = increments.barKg
        let last = test(at: workingKg, reps: reps, targetRIR: targetRIR)
        guard workingKg > bar + 0.01 else { return [last] }
        var sets = [SetPrescription(kind: .warmup, loadKg: bar, targetReps: min(10, max(5, reps)), targetRIR: 5)]
        let gap = workingKg - bar
        let jumps = min(3, max(0, Int((gap / 30).rounded(.up)) - 1))
        var previous = bar
        for step in 0..<jumps {
            let load = increments.round(bar + gap * Double(step + 1) / Double(jumps + 1), down: true)
            guard load > previous + 0.01, load < workingKg - 0.01 else { continue }
            sets.append(climbing(load, to: workingKg, reps: reps))
            previous = load
        }
        return sets + [last]
    }

    /// The biggest plate that goes on at least once under the work, a pair more each set, up to
    /// four sets spread evenly and ending on the heaviest: every one lighter than the work, which
    /// follows straight on. Nil when even the smallest pair is too much.
    static func plateRamp(to workingKg: Double, reps: Int, increments: GymIncrements) -> [SetPrescription]? {
        let unit = increments.gym.unit
        let work = unit.fromKilograms(workingKg)
        let base = increments.base
        let sizes = increments.gym.plates.filter { $0 > 0 }.sorted(by: >)
        guard let plate = sizes.first(where: { base + 2 * $0 < work - 0.01 }) else { return nil }
        var loads: [Double] = []
        var load = base + 2 * plate
        while load < work - 0.01 {
            loads.append(load)
            load += 2 * plate
        }
        if loads.count > 4 {
            let all = loads
            loads = (1...4).map { all[Int((Double($0) * Double(all.count) / 4).rounded(.up)) - 1] }
        }
        return loads.map { climbing(unit.toKilograms($0), to: workingKg, reps: reps) }
    }

    /// About half and three quarters of the work, and 45, 65 and 82% once it's heavy.
    static func ramp(to workingKg: Double, reps: Int, increments: GymIncrements) -> [SetPrescription] {
        let fractions = workingKg >= 60 ? [0.45, 0.65, 0.82] : [0.5, 0.75]
        var previous = 0.0
        return fractions.compactMap { fraction in
            let load = increments.round(workingKg * fraction, down: true)
            guard load > previous + 0.01, load < workingKg - 0.01 else { return nil }
            previous = load
            return climbing(load, to: workingKg, reps: reps)
        }
    }

    /// A set on the way up: fewer reps the nearer it gets to the work, and never more than the work asks.
    static func climbing(_ load: Double, to workingKg: Double, reps: Int) -> SetPrescription {
        let fraction = load / workingKg
        let usual = fraction <= 0.5 + 1e-9 ? 8 : (fraction <= 0.75 + 1e-9 ? 5 : 3)
        return SetPrescription(kind: .warmup, loadKg: load, targetReps: min(usual, max(reps, 3)), targetRIR: 5)
    }

    /// The working weight for two to four reps (about half the work's), well short of the work.
    static func test(at workingKg: Double, reps: Int, targetRIR: Double) -> SetPrescription {
        let testReps = max(1, min(4, max(2, (reps + 1) / 2), reps - 1))
        let reserve = max(targetRIR, min(5, targetRIR + Double(reps - testReps)))
        return SetPrescription(kind: .warmup, loadKg: workingKg, targetReps: testReps, targetRIR: reserve)
    }
}
