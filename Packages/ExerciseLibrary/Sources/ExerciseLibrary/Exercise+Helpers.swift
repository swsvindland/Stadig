import Foundation
import SystemCore

extension Exercise {
    /// How much another exercise trains this one's primary muscles: the mean of its weights for them,
    /// so 1 when it drives all of them as a primary mover. Falls back to every listed muscle when this
    /// one has no primary mover (warm-ups list theirs at half weight).
    func primaryOverlap(with other: Exercise) -> Double {
        let primary = primaryMuscles.isEmpty ? muscles.map(\.muscle) : primaryMuscles
        guard !primary.isEmpty else { return 0 }
        return primary.reduce(0) { $0 + min(1, other.weight(of: $1)) } / Double(primary.count)
    }

    /// Each trains at least half of the other's primary muscles.
    func sharesPrimaryMuscles(with other: Exercise) -> Bool {
        primaryOverlap(with: other) >= 0.5 && other.primaryOverlap(with: self) >= 0.5
    }

    /// Cosine similarity of the two muscle profiles, 0–1.
    func similarity(to other: Exercise) -> Double {
        let dot = muscles.reduce(0) { $0 + $1.weight * other.weight(of: $1.muscle) }
        let norms = muscles.magnitude * other.muscles.magnitude
        return norms > 0 ? dot / norms : 0
    }

    /// The summed stress this exercise puts on the given joints.
    func totalStress(on joints: Set<Joint>) -> Int {
        self.joints.filter { joints.contains($0.joint) }.reduce(0) { $0 + $1.stress.rawValue }
    }

    /// Warm-ups and drills done on cardio equipment: the general opener.
    var isCardio: Bool { equipment.isCardio }

    /// Whether a warm-up or drill mostly prepares the legs and hips.
    var preparesLowerBody: Bool {
        let legs = muscles.filter { $0.muscle.region == .legs }.reduce(0) { $0 + $1.weight }
        let rest = muscles.filter { $0.muscle.region != .legs }.reduce(0) { $0 + $1.weight }
        return legs > rest
    }
}

extension [MuscleShare] {
    var magnitude: Double { reduce(0) { $0 + $1.weight * $1.weight }.squareRoot() }
}

extension Equipment {
    enum Family { case freeWeight, machine, bodyweight, cardio }

    /// Broad kinds of equipment, for "closest equivalent" in substitutions.
    var family: Family {
        if isFreeWeight { return .freeWeight }
        if isMachine { return .machine }
        if isCardio { return .cardio }
        return .bodyweight
    }
}
