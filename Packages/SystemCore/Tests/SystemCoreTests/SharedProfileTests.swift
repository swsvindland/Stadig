import Foundation
import Testing

@testable import SystemCore

/// The shared profile as Stadig Lift leaves it: its training days and classes, whoever wrote the file.
@Suite("The shared profile")
struct SharedProfileTests {
    func profile(days: [Weekday], recurring: [RecurringActivity] = []) -> SharedProfile {
        SharedProfile(
            schedule: TrainingSchedule(daysPerWeek: days.count, minutesPerSession: 90, preferredDays: days), recurring: recurring,
            createdBy: .liftTrack)
    }

    @Test func stadigLiftFillsAMissingFileAndRepairsAWrongOne() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let own = profile(days: [.monday], recurring: [RecurringActivity(activity: .bjj, weekdays: [.tuesday])])
        #expect(own.sharing(over: nil, writtenBy: nil, now: now) == own)
        #expect(own.sharing(over: own, writtenBy: .liftTrack, now: now) == nil)

        // Stadig Macro's copy, with its own edit and nothing of the classes.
        var other = SharedProfile(createdBy: .macroTrack)
        other.heightCm = 180
        let repaired = own.sharing(over: other, writtenBy: .macroTrack, now: now)
        #expect(repaired?.recurring == own.recurring)
        #expect(repaired?.schedule == own.schedule)
        #expect(repaired?.heightCm == 180)
        #expect(repaired?.updatedAt == now)
    }

    /// Classes edited on the iPad reach the iPhone's file before the profile record does.
    @Test func stadigLiftLeavesItsOwnNewerEditFromAnotherDevice() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var own = profile(days: [.monday])
        own.updatedAt = now.addingTimeInterval(-3600)
        var edited = profile(days: [.monday], recurring: [RecurringActivity(activity: .bjj, weekdays: [.tuesday])])
        edited.updatedAt = now.addingTimeInterval(-60)
        #expect(own.sharing(over: edited, writtenBy: .liftTrack, now: now) == nil)
        #expect(own.sharing(over: edited, writtenBy: .macroTrack, now: now) != nil, "another app's copy still gets repaired")
    }
}
