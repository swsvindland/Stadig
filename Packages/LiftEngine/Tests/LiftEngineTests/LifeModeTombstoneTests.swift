import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// A deleted life mode is kept as a tombstone so the delete reaches the other apps; the engine
/// must treat it as if it had never been set.
@Suite("Deleted life modes")
struct LifeModeTombstoneTests {
    @Test func aDeletedVacationIsNeverSeen() {
        let mesocycle = ProgramGenerator.generate(Fixture.input(Fixture.profile()))
        let today = mesocycle.block.start.adding(days: 10)
        let trip = LifeModePeriod(kind: .vacation, start: today.adding(days: 1), end: today.adding(days: 8), createdBy: .liftTrack)
        func state(_ lifeModes: [LifeModePeriod]) -> LiftState {
            LiftState(
                profile: Fixture.profile(), settings: LiftSettings(), gym: Gym.preset(.fullGym, unit: .kg), catalog: Fixture.catalog,
                mesocycles: [mesocycle], lifeModes: lifeModes, bodyweightKg: 80, today: today)
        }
        let deleted = state([trip.deleted()])
        #expect(deleted.lifeModes.isEmpty)
        #expect(Analyst.analyse(deleted).block == Analyst.analyse(state([])).block)
    }

    @Test func twoSourcesNamingOneTargetGiveOnePriority() {
        let priorities = [
            TrainingPriority(target: .conditioning, emphasis: 1, reason: "Fitter for the season", source: .hub),
            TrainingPriority(target: .conditioning, emphasis: 0.5, reason: "Coach note", source: .hub),
        ].mergedByID()
        #expect(priorities.count == 1)
        #expect(Set(priorities.map(\.id)).count == priorities.count)
    }
}
