import Foundation
import SystemCore

/// What the library can be narrowed by: the kind of work, the movement, the equipment, a muscle, a
/// joint to go easy on, the person's gym and their injuries. Every filter that's set must match.
public struct ExerciseFilter: Hashable, Sendable {
    public var kind: ExerciseKind?
    public var pattern: MovementPattern?
    public var equipment: Equipment?
    /// Trains this muscle, as a primary mover or a secondary one.
    public var muscle: Muscle?
    /// Loads this joint lightly or not at all: "easy on the knees".
    public var easyOn: Joint?
    /// Only what this place can do (`Availability.allows`, overrides included); nil for anywhere.
    public var availability: Availability?
    /// Only what none of these injuries rules out (`Injury.excludes`, the person's overrides
    /// included); nil for no injury filter.
    public var injuries: [Injury]?

    public init(
        kind: ExerciseKind? = nil, pattern: MovementPattern? = nil, equipment: Equipment? = nil, muscle: Muscle? = nil,
        easyOn: Joint? = nil, availability: Availability? = nil, injuries: [Injury]? = nil
    ) {
        self.kind = kind
        self.pattern = pattern
        self.equipment = equipment
        self.muscle = muscle
        self.easyOn = easyOn
        self.availability = availability
        self.injuries = injuries
    }

    /// No filter set: the whole library.
    public var isEmpty: Bool { self == ExerciseFilter() }

    public func includes(_ exercise: Exercise) -> Bool {
        if let kind, exercise.kind != kind { return false }
        if let pattern, exercise.pattern != pattern { return false }
        if let equipment, exercise.equipment != equipment { return false }
        if let muscle, exercise.weight(of: muscle) <= 0 { return false }
        if let easyOn, let stress = exercise.stress(on: easyOn), stress > .low { return false }
        if let availability, !availability.allows(exercise) { return false }
        if let injuries, injuries.contains(where: { $0.excludes(exercise) }) { return false }
        return true
    }

    /// The exercises that pass, best first. A query ranks them as `ExerciseSearch` does. Without
    /// one, a muscle filter puts the exercises that train it hardest first (primary movers before
    /// secondary ones); otherwise they keep the library's order.
    public func apply(to exercises: [Exercise], query: String = "") -> [Exercise] {
        let passing = exercises.filter(includes)
        let boost: (Exercise) -> Double = { exercise in muscle.map { exercise.weight(of: $0) } ?? 0 }
        return ExerciseSearch.search(passing, query, boost: boost)
    }

    /// The movement patterns among exercises of a kind (every kind when nil), in the vocabulary's
    /// order: what a pattern menu offers, so it never lists one with nothing behind it.
    public static func patterns(in exercises: [Exercise], kind: ExerciseKind?) -> [MovementPattern] {
        let present = Set(exercises.filter { kind == nil || $0.kind == kind }.map(\.pattern))
        return MovementPattern.allCases.filter(present.contains)
    }

    /// The equipment among exercises of a kind (every kind when nil), in the vocabulary's order.
    public static func equipment(in exercises: [Exercise], kind: ExerciseKind?) -> [Equipment] {
        let present = Set(exercises.filter { kind == nil || $0.kind == kind }.map(\.equipment))
        return Equipment.allCases.filter(present.contains)
    }
}
