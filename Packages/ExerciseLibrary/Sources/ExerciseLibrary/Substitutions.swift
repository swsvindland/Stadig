import Foundation
import SystemCore

/// Injury mode's deterministic filter over the library.
public enum InjuryFilter {
    /// The exercises no active injury rules out (`Injury.excludes`, including the person's overrides).
    public static func allowed(_ exercises: [Exercise], injuries: [Injury]) -> [Exercise] {
        exercises.filter { exercise in !injuries.contains { $0.excludes(exercise) } }
    }
}

/// Swaps: for another gym, an injury, an exercise the person avoids, or a tight Fatigue Budget.
public enum Substitutions {
    /// Replacements for an exercise, best first: the same movement pattern first, then other
    /// exercises of the same kind that share its primary muscles (overlap ≥ 0.5 both ways, so a row
    /// never suggests a front squat for the upper back they both touch). Filtered by
    /// availability (nil means anything), injuries and the avoid set. Among equal matches, lower
    /// stress on injured joints wins, then a higher stimulus-to-fatigue ratio, then library order.
    public static func candidates(for exercise: Exercise, in catalog: [Exercise], availability: Availability?,
                                  injuries: [Injury] = [], avoid: Set<String> = [], limit: Int = 12) -> [Exercise] {
        let injured = injuries.reduce(into: Set<Joint>()) { $0.formUnion($1.joints) }
        let ranked = catalog.enumerated().compactMap { offset, other -> Ranked? in
            guard other.id != exercise.id, other.kind == exercise.kind, !avoid.contains(other.id),
                  usable(other, availability: availability, injuries: injuries) else { return nil }
            let overlap = exercise.primaryOverlap(with: other)
            let samePattern = other.pattern == exercise.pattern
            guard samePattern ? overlap > 0 || exercise.muscles.isEmpty : exercise.sharesPrimaryMuscles(with: other) else { return nil }
            var score = (samePattern ? 10 : 0) + overlap * 4
            score += exercise.equipment == other.equipment ? 1 : exercise.equipment.family == other.equipment.family ? 0.5 : 0
            score += exercise.unilateral == other.unilateral ? 0.5 : 0
            score -= exercise.timed == other.timed ? 0 : 2
            if let category = exercise.strength?.category, other.strength?.category == category { score += 1 }
            // Closest in heaviness: a barbell bench should become a dumbbell press, not a squeeze press.
            score -= abs(exercise.fatigue.systemic - other.fatigue.systemic) * 2
            return Ranked(exercise: other, primary: rounded(score), secondary: 0,
                          injuredStress: other.totalStress(on: injured), sfr: other.fatigue.sfr, offset: offset)
        }
        return ranked.sorted().prefix(max(0, limit)).map(\.exercise)
    }

    /// Cheaper ways to train the same primary muscles: strictly lower systemic fatigue and a higher
    /// stimulus-to-fatigue ratio. Same pattern first (a conventional deadlift gives hip hinges such as
    /// RDLs), then other work for those muscles (hamstring and lower-back work). Within each, the best
    /// trade of a similar muscle profile, a strong stimulus and a real saving comes first, so a sumo
    /// deadlift (barely cheaper) ranks below a dumbbell RDL.
    public static func lowerSystemicCost(for exercise: Exercise, in catalog: [Exercise], availability: Availability?,
                                         injuries: [Injury] = []) -> [Exercise] {
        let injured = injuries.reduce(into: Set<Joint>()) { $0.formUnion($1.joints) }
        let ranked = catalog.enumerated().compactMap { offset, other -> Ranked? in
            guard other.id != exercise.id, other.kind == exercise.kind,
                  other.fatigue.systemic < exercise.fatigue.systemic, other.fatigue.sfr > exercise.fatigue.sfr,
                  exercise.sharesPrimaryMuscles(with: other),
                  usable(other, availability: availability, injuries: injuries) else { return nil }
            let saving = 1 - other.fatigue.systemic / exercise.fatigue.systemic
            let value = exercise.similarity(to: other) * other.fatigue.stimulus + saving * 0.5
            return Ranked(exercise: other, primary: other.pattern == exercise.pattern ? 1 : 0, secondary: (value * 50).rounded() / 50,
                          injuredStress: other.totalStress(on: injured), sfr: other.fatigue.sfr, offset: offset)
        }
        return ranked.sorted().map(\.exercise)
    }

    /// A day's exercises for this place and these injuries: each kept if allowed, otherwise the best
    /// candidate the day doesn't already use; nil when nothing fits.
    public static func standIns(_ planned: [Exercise], in catalog: [Exercise], availability: Availability,
                                injuries: [Injury] = []) -> [Exercise?] {
        var taken = Set(planned.filter { usable($0, availability: availability, injuries: injuries) }.map(\.id))
        return planned.map { exercise in
            if usable(exercise, availability: availability, injuries: injuries) { return exercise }
            guard let found = candidates(for: exercise, in: catalog, availability: availability, injuries: injuries,
                                         avoid: taken, limit: 1).first else { return nil }
            taken.insert(found.id)
            return found
        }
    }

    static func usable(_ exercise: Exercise, availability: Availability?, injuries: [Injury]) -> Bool {
        (availability?.allows(exercise) ?? true) && !injuries.contains { $0.excludes(exercise) }
    }

    private static func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    /// A candidate and its sort keys, best first.
    private struct Ranked: Comparable {
        var exercise: Exercise
        var primary: Double
        var secondary: Double
        var injuredStress: Int
        var sfr: Double
        var offset: Int

        static func < (a: Ranked, b: Ranked) -> Bool {
            if a.primary != b.primary { return a.primary > b.primary }
            if a.secondary != b.secondary { return a.secondary > b.secondary }
            if a.injuredStress != b.injuredStress { return a.injuredStress < b.injuredStress }
            if a.sfr != b.sfr { return a.sfr > b.sfr }
            return a.offset < b.offset
        }

        static func == (a: Ranked, b: Ranked) -> Bool { a.offset == b.offset }
    }
}
