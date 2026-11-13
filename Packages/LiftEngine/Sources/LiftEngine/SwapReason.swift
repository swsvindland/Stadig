import ExerciseLibrary
import Foundation
import SystemCore

/// Why a stand-in fits, in a few words, under each candidate in the session's swap: what it shares
/// with the exercise it replaces, what it's done with, and what it spares.
public enum SwapReason {
    /// "Same movement · Dumbbells", "Same muscles · Plate-loaded machines · Less tiring", and with an
    /// injury, "Same movement · Dumbbells · Easier on your shoulder".
    public static func line(for candidate: Exercise, replacing exercise: Exercise, injuries: [Injury] = []) -> String {
        var parts = [candidate.pattern == exercise.pattern ? "Same movement" : "Same muscles", candidate.equipment.label]
        // Only the injured joints the stand-in loads less than the original.
        let injured = injuries.reduce(into: Set<Joint>()) { $0.formUnion($1.joints) }
        let spared = Joint.allCases.filter { injured.contains($0) && stress(candidate, on: $0) < stress(exercise, on: $0) }
        if !spared.isEmpty {
            let names = spared.map { $0.label.lowercased() }
            let joined = names.count == 1 ? names[0] : "\(names.dropLast().joined(separator: ", ")) and \(names.last ?? "")"
            parts.append("Easier on your \(joined)")
        }
        // A quarter lighter on the whole body is worth saying; a little lighter isn't.
        if exercise.fatigue.systemic > 0, candidate.fatigue.systemic <= exercise.fatigue.systemic * 0.75 { parts.append("Less tiring") }
        return parts.joined(separator: " · ")
    }

    private static func stress(_ exercise: Exercise, on joint: Joint) -> Int {
        exercise.joints.filter { $0.joint == joint }.reduce(0) { $0 + $1.stress.rawValue }
    }
}
