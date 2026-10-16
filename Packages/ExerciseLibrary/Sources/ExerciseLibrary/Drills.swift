import Foundation
import SystemCore

/// The non-strength parts of a session: mobility drills, warm-ups, stretches and conditioning.
public enum Drills {
    /// Mobility drills for a target, those aimed mainly at it first, in library order otherwise.
    public static func mobility(for target: MobilityTarget, in catalog: [Exercise], availability: Availability?) -> [Exercise] {
        let drills = catalog.filter { $0.kind == .mobility && $0.mobilityTargets.contains(target) && allows(availability, $0) }
        return drills.filter { $0.mobilityTargets.first == target } + drills.filter { $0.mobilityTargets.first != target }
    }

    /// A warm-up routine for an upper or lower day, in order: one general cardio opener when the
    /// place has the equipment, then that day's moves.
    public static func warmup(lowerBody: Bool, in catalog: [Exercise], availability: Availability?) -> [Exercise] {
        let available = catalog.filter { $0.kind == .warmup && allows(availability, $0) }
        let opener = available.first(where: \.isCardio)
        let moves = available.filter { !$0.isCardio && $0.preparesLowerBody == lowerBody }
        return (opener.map { [$0] } ?? []) + moves
    }

    /// Static stretches for the muscles trained, in the order the muscles are given: stretches that
    /// target a muscle directly come before those that reach it secondarily.
    public static func stretches(for muscles: [Muscle], in catalog: [Exercise]) -> [Exercise] {
        let stretches = catalog.filter { $0.kind == .stretch }
        var result: [Exercise] = []
        var seen = Set<String>()
        for primary in [true, false] {
            for muscle in muscles {
                for stretch in stretches where !seen.contains(stretch.id) {
                    let weight = stretch.weight(of: muscle)
                    if primary ? weight >= 1 : weight > 0 {
                        result.append(stretch)
                        seen.insert(stretch.id)
                    }
                }
            }
        }
        return result
    }

    /// Conditioning work the place allows, optionally only steady or only intervals, in library order.
    public static func conditioning(in catalog: [Exercise], availability: Availability?, style: ConditioningSpec.Style?) -> [Exercise] {
        catalog.filter { exercise in
            guard exercise.kind == .conditioning, let spec = exercise.conditioning, allows(availability, exercise) else { return false }
            return style.map { spec.style == $0 } ?? true
        }
    }

    /// Heat after training the place has: the sauna first, then the steam room.
    public static func recovery(in catalog: [Exercise], availability: Availability?) -> [Exercise] {
        catalog.filter { $0.kind == .recovery && allows(availability, $0) }
    }

    private static func allows(_ availability: Availability?, _ exercise: Exercise) -> Bool {
        availability?.allows(exercise) ?? true
    }
}
