import ExerciseLibrary
import Foundation
import SystemCore

/// Where the assessment stands, with the weekly "what we've learned" notes that make it feel like
/// progress rather than waiting.
public struct AssessmentStatus: Hashable, Sendable {
    /// 1-based.
    public var week: Int
    public var totalWeeks: Int
    public var workingWeightsFound: Int
    public var exercisesTotal: Int
    public var scoredLifts: Int
    public var learned: [String]
    public var complete: Bool
    /// Experienced lifters whose ratings have proven accurate can finish the lifting side early.
    public var canFinishEarly: Bool

    public var progress: Double { Double(min(week, totalWeeks)) / Double(max(1, totalWeeks)) }
}

/// What comes after the assessment, and why.
public struct NextBlockDecision: Hashable, Sendable {
    public var kind: BlockKind
    public var phase: NutritionPhase
    public var reason: String
    /// Whether the person should be asked the one-tap phase question first.
    public var askPhase: Bool
}

public enum Assessment {
    public static func status(
        _ mesocycle: Mesocycle, sessions: [SessionRecord], trust: TrustState, strength: StrengthProfile,
        catalog: ExerciseCatalog, today: Day
    ) -> AssessmentStatus {
        let block = mesocycle.block
        let week = max(1, min(block.loadingWeeks, block.start.days(until: today) / 7 + 1))
        let mine = sessions.filter { $0.mesocycleID == mesocycle.id }
        let exercises = mesocycle.exerciseIDs
        let found = exercises.filter { id in mine.contains { $0.workSets.contains { $0.exerciseID == id && $0.kind != .findingWeight } } }
        var learned: [String] = []

        if mine.isEmpty {
            learned.append("Nothing yet: your first session sets the starting point for every exercise.")
        } else {
            learned.append("Working weights found for \(found.count) of \(exercises.count) exercises.")
        }
        let checks = trust.evidenceCount
        if checks > 0 {
            learned.append("\(trust.label) (\(checks) check\(checks == 1 ? "" : "s") so far).")
            if let tendency = trust.tendency { learned.append(tendency) }
        }
        let scored = strength.categories
        if !scored.isEmpty {
            let parts = scored.sorted { $0.score > $1.score }.prefix(3).map {
                "\($0.category.label.lowercased()) \(Int($0.score.rounded())) (\($0.level.lowercased()))"
            }
            learned.append("Early strength read: \(parts.joined(separator: ", ")).")
        }
        if week >= 3, let first = strength.priorities.first { learned.append("Imbalance spotted: \(first.reason)") }

        let complete =
            today > block.loadingEnd
            || (week >= block.loadingWeeks && found.count == exercises.count && mine.count >= 2 * mesocycle.days.count * (block.loadingWeeks - 1))
        let canFinishEarly = !complete && week >= 2 && trust.provenAccurate && found.count == exercises.count
        if canFinishEarly { learned.append("Your ratings have proven reliable, so you can finish the lifting assessment early.") }
        return AssessmentStatus(
            week: week, totalWeeks: block.loadingWeeks, workingWeightsFound: found.count, exercisesTotal: exercises.count,
            scoredLifts: scored.count, learned: learned, complete: complete, canFinishEarly: canFinishEarly)
    }

    /// After the assessment: a standard block when the phase is known (from Stadig Macro, or the
    /// person's one-tap answer); a neutral block while Stadig Macro is still deciding.
    public static func nextBlock(nutrition: NutritionSummary?, selfReported: SelfReportedPhase?) -> NextBlockDecision {
        if let phase = nutrition?.phase {
            return NextBlockDecision(
                kind: .standard, phase: phase, reason: "Stadig Macro has set your phase: \(phase.kind.label.lowercased()).", askPhase: false)
        }
        if nutrition != nil {
            return NextBlockDecision(
                kind: .neutral, phase: .assumedMaintenance,
                reason:
                    "Stadig Macro is still learning your maintenance, so this block is general strength and size that works in any phase. Volume adjusts at the next boundary.",
                askPhase: false)
        }
        if let selfReported {
            return NextBlockDecision(
                kind: .standard, phase: selfReported.phase,
                reason: selfReported == .notSure
                    ? "Phase not known, so maintenance is assumed." : "Planned for \(selfReported.label.lowercased()), as you said.",
                askPhase: false)
        }
        return NextBlockDecision(kind: .standard, phase: .assumedMaintenance, reason: "Are you cutting, maintaining or bulking?", askPhase: true)
    }
}

extension TrainingBlock {
    var loadingEnd: Day { start.adding(days: loadingWeeks * 7 - 1) }
}
