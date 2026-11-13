import ExerciseLibrary
import SystemCore
import Testing

@testable import LiftEngine

/// The line under each candidate in the session's swap.
struct SwapReasonTests {
    private func exercise(_ id: String) -> Exercise { Fixture.catalog.resolve(id) }

    @Test func sameMovementNamesTheEquipment() {
        let line = SwapReason.line(for: exercise("db-bench-press"), replacing: exercise("barbell-bench-press"))
        #expect(line == "Same movement · Dumbbells")
    }

    @Test func anotherMovementForTheSameMusclesThatsLighter() {
        let line = SwapReason.line(for: exercise("leg-press"), replacing: exercise("barbell-back-squat"))
        #expect(line == "Same muscles · Plate-loaded machines · Less tiring")
    }

    @Test func anInjuredJointItLoadsLessIsNamed() {
        let shoulder = Injury(parts: [InjuredPart(.shoulder)], severity: .mild)
        let line = SwapReason.line(for: exercise("db-bench-press"), replacing: exercise("barbell-bench-press"), injuries: [shoulder])
        #expect(line == "Same movement · Dumbbells · Easier on your shoulder")
    }

    @Test func anInjuredJointItLoadsAsMuchIsNot() {
        let elbow = Injury(parts: [InjuredPart(.elbow)], severity: .mild)
        let line = SwapReason.line(for: exercise("db-bench-press"), replacing: exercise("barbell-bench-press"), injuries: [elbow])
        #expect(line == "Same movement · Dumbbells")
    }

    /// Head to foot, as the joints are listed.
    @Test func severalSparedJointsInOneLine() {
        let legs = Injury(parts: [InjuredPart(.knee), InjuredPart(.lowerBack)], severity: .moderate)
        let line = SwapReason.line(for: exercise("goblet-squat"), replacing: exercise("barbell-back-squat"), injuries: [legs])
        #expect(line == "Same movement · Dumbbells · Easier on your lower back and knee · Less tiring")
    }
}
