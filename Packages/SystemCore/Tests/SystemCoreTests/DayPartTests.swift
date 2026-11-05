import Foundation
import Testing

@testable import SystemCore

@Suite("Day parts and commitments")
struct DayPartTests {
    let utc = TimeZone(identifier: "UTC")!
    let monday = Day(year: 2026, month: 11, day: 2)

    func lift(on day: Day, hour: Int) -> SessionSummary {
        SessionSummary(id: UUID(), app: .liftTrack, kind: .strength, start: day.at(hour: hour, minute: 0, timeZone: utc), minutes: 60, planned: true)
    }

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

    @Test func aPackedMondayHasTheLiftAndBothClasses() {
        let classes = [
            RecurringActivity(activity: .bjj, weekdays: [.monday, .wednesday], minutes: 60),
            RecurringActivity(activity: .muayThai, weekdays: [.monday, .wednesday], minutes: 60),
        ]
        let lifts = (1...8).map { lift(on: monday.adding(days: -$0), hour: 6) }
        let week = WeekCommitments(
            profile: profile(days: [.monday, .wednesday, .friday], recurring: classes),
            lift: AppSummary(app: .liftTrack, sessions: lifts), before: monday, timeZone: utc)
        #expect(week.on(.monday).map(\.title) == ["Lift", "BJJ", "Muay Thai"])
        #expect(week.on(.monday).map(\.part) == [.early, .evening, .evening])
        #expect(week.on(.friday).map(\.title) == ["Lift"])
        #expect(week.on(.tuesday).isEmpty)
    }

    /// Stadig Macro can write the profile first, with the default three days nobody chose.
    @Test func noLiftsBeforeStadigLiftHasPublished() {
        let classes = [RecurringActivity(activity: .bjj, weekdays: [.tuesday])]
        let week = WeekCommitments(profile: profile(days: [.monday], recurring: classes), lift: nil, before: monday, timeZone: utc)
        #expect(week.on(.monday).isEmpty)
        #expect(week.on(.tuesday).map(\.title) == ["BJJ"])
    }

    @Test func aLiftWithNoHistoryIsTakenToBeInTheEvening() {
        let week = WeekCommitments(profile: profile(days: [.monday]), lift: AppSummary(app: .liftTrack), before: monday, timeZone: utc)
        #expect(week.on(.monday).map(\.part) == [.evening])
    }

    @Test func todaysLiftDoesntMoveThePlanUnderTheDay() {
        let usual = (1...4).map { lift(on: monday.adding(days: -$0), hour: 6) }
        let tonight = lift(on: monday, hour: 21)
        #expect(WeekCommitments.liftingPart(usual + [tonight], before: monday, timeZone: utc) == .early)
    }

    @Test func noProfileMeansNoCommitments() {
        #expect(WeekCommitments(profile: nil, lift: AppSummary(app: .liftTrack), before: monday) == .none)
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
