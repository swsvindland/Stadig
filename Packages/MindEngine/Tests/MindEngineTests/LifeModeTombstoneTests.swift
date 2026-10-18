import Foundation
import Testing
import SystemCore
@testable import MindEngine

/// A deleted life mode is kept as a tombstone so the delete reaches the other apps; study must
/// carry on as if it had never been set.
@Suite("Deleted life modes")
struct LifeModeTombstoneTests {
    @Test func aDeletedVacationDoesNotPauseStudy() {
        let today = Day(year: 2026, month: 10, day: 16)
        let trip = LifeModePeriod(kind: .vacation, start: today.adding(days: -2), end: today.adding(days: 5), createdBy: .liftTrack)
        #expect(StudyCalendar.pause(on: today, lifeModes: [trip]) == .vacation)
        #expect(StudyCalendar.pause(on: today, lifeModes: [trip.deleted()]) == nil)
    }
}
