import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// A deleted life mode is kept as a tombstone so the delete reaches the other apps; the engine
/// must treat it as if it had never been set.
@Suite("Deleted life modes")
struct LifeModeTombstoneTests {
    @Test func aDeletedIllnessIsNeverSeen() {
        let today = Day(year: 2026, month: 10, day: 16)
        let ill = LifeModePeriod(kind: .illness(.systemic), start: today.adding(days: -3), end: today, createdBy: .macroTrack)
        let state = MacroState(
            profile: profile(), settings: MacroSettings(assessmentStart: today.adding(days: -20)),
            lifeModes: [ill.deleted()], today: today)
        #expect(state.lifeModes.isEmpty)
        #expect(!LifeModes.effects(on: today, periods: state.lifeModes).disciplineExempt)
    }
}
