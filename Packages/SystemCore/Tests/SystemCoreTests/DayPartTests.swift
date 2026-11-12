import Foundation
import Testing

@testable import SystemCore

@Suite("Day parts and the shared profile")
struct DayPartTests {
    func profile(days: [Weekday], recurring: [RecurringActivity] = []) -> SharedProfile {
        SharedProfile(
            schedule: TrainingSchedule(daysPerWeek: days.count, minutesPerSession: 90, preferredDays: days), recurring: recurring,
            createdBy: .liftTrack)
    }

    @Test func hoursFallInOnePartEach() {
        #expect(DayPart(hour: 6) == .early)
        #expect(DayPart(hour: 8) == .morning)
        #expect(DayPart(hour: 13) == .midday)
        #expect(DayPart(hour: 14) == .afternoon)
        #expect(DayPart(hour: 19) == .evening)
        #expect(DayPart(hour: 22) == .night)
        // The small hours are the night before's, as a study day's are.
        #expect(DayPart(hour: 1) == .night)
    }

    @Test func thePublishedWordRoundTripsThroughItsOwnPart() {
        for time in TimeOfDay.allCases { #expect(DayPart(time).timeOfDay == time) }
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
