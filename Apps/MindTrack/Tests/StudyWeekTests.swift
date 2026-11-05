import Foundation
import MindEngine
import SystemCore
import SystemStore
import Testing

@testable import MindTrack

/// The app's side of the week: what it reads from Stadig Lift, what it keeps, and what it starts.
@MainActor
@Suite("The study week")
struct StudyWeekTests {
    /// Monday 12 October 2026, 10:00 here.
    let monday = TestApp.wednesday.addingTimeInterval(-2 * 86_400)

    func busyProfile() -> SharedProfile {
        SharedProfile(
            schedule: TrainingSchedule(daysPerWeek: 3, minutesPerSession: 90, preferredDays: [.monday, .wednesday, .friday]),
            recurring: [
                RecurringActivity(activity: .bjj, weekdays: [.monday, .wednesday], minutes: 60),
                RecurringActivity(activity: .muayThai, weekdays: [.monday, .wednesday], minutes: 60),
            ], createdBy: .liftTrack)
    }

    func publish(_ profile: SharedProfile, on shared: SharedContainer) throws {
        try shared.write(profile, to: .profile, by: .liftTrack)
        try shared.write(AppSummary(app: .liftTrack), to: .summary(.liftTrack), by: .liftTrack)
    }

    @Test func someoneSetUpBeforeBlocksGetsAWeekFromTheirCourses() throws {
        let clock = TestClock()
        let model = TestApp.onboardedModel([.japanese, .maths], clock: clock)
        let week = try #require(model.weekSettings)
        #expect(week.blocks(.japanese) == 4)
        #expect(week.blocks(.maths) == 4)
        #expect(week.since == model.today)
        #expect(model.store.all(WeekSettings.self).count == 1)
    }

    /// A week set up on another device, still on its way down, mustn't lose to a seed made here.
    @Test func aWeekFromAnotherDeviceWinsOverTheSeed() throws {
        let store = TestApp.store()
        let clock = TestClock()
        let model = TestApp.onboardedModel([.japanese], store: store, clock: clock)
        var theirs = try #require(model.weekSettings)
        theirs.setBlocks(6, for: .japanese)
        theirs.updatedAt = clock.now.addingTimeInterval(-3600)
        store.save(theirs)
        model.reload()
        #expect(model.weekSettings?.blocks(.japanese) == 6)
    }

    @Test func nothingIsSeededBeforeSetup() {
        let model = TestApp.model()
        #expect(model.weekSettings == nil)
    }

    @Test func aPackedDayFromStadigLiftHasNoBlocksAndSaysWhy() throws {
        let clock = TestClock(monday)
        let shared = TestApp.sharedContainer()
        try publish(busyProfile(), on: shared)
        let model = TestApp.onboardedModel([.japanese, .reading], shared: shared, clock: clock)
        // The week began before today: a first block after onboarding isn't what's being tested.
        model.save(
            week: {
                var week = model.weekSettings!
                week.since = model.today.adding(days: -7)
                return week
            }())
        let analysis = try #require(model.analysis)
        #expect(analysis.blocks.isEmpty)
        // With no lifts published yet, the lift is taken to be in the evening with the classes.
        #expect(analysis.commitments.map(\.title) == ["BJJ", "Lift", "Muay Thai"])
        #expect(analysis.week[0].blocks.isEmpty)
        #expect(analysis.week[1].blocks.count >= 1)
    }

    @Test func aClassAddedInStadigLiftReachesTheNextRead() throws {
        let clock = TestClock(monday)
        let shared = TestApp.sharedContainer()
        let model = TestApp.onboardedModel([.japanese], shared: shared, clock: clock)
        #expect(model.commitments == .none)
        try publish(busyProfile(), on: shared)
        model.readShared()
        #expect(model.commitments.on(.monday).count == 3)
    }

    @Test func aPartOpenedByHandTakesABlockAndClosingForgetsIt() throws {
        let clock = TestClock(monday)
        let shared = TestApp.sharedContainer()
        try publish(busyProfile(), on: shared)
        let model = TestApp.onboardedModel([.japanese], shared: shared, clock: clock)
        model.togglePart(.monday, .night)
        #expect(model.weekSettings?.override(.monday, .night) == true)
        model.togglePart(.monday, .night)
        #expect(model.weekSettings?.parts.isEmpty == true)
    }

    @Test func anAmountKeepsTheTiersOlderBuildsRead() throws {
        let model = TestApp.onboardedModel([.japanese, .maths])
        model.setAmount(0, for: .maths)
        #expect(model.weekSettings?.blocks(.maths) == 0)
        #expect(model.settings?.mode(.maths) == .maintenance)
        model.setAmount(WeekSettings.courseOff, for: .maths)
        #expect(model.settings?.has(.maths) == false)
    }

    @Test func aPinIsKept() {
        let model = TestApp.onboardedModel([.maths])
        model.setPin(.morning, for: .maths)
        #expect(model.weekSettings?.pin(.maths) == .morning)
        model.setPin(nil, for: .maths)
        #expect(model.weekSettings?.pin(.maths) == nil)
    }

    @Test func theWeekKeepsWhatItAskedFor() throws {
        let model = TestApp.onboardedModel([.japanese])
        let layout = try #require(model.analysis?.layout)
        #expect(model.weekSettings?.target(layout.monday) == layout.ledger)
    }

    @Test func aConversationCountsTowardsTheWeek() throws {
        let model = TestApp.onboardedModel([.japanese])
        model.logConversation(.japanese)
        let layout = try #require(model.analysis?.layout)
        #expect(layout.done[.japanese] == 1)
    }

    @Test func aBlockIsOneCourseWhateverWasAsked() {
        let model = TestApp.onboardedModel([.maths, .writing])
        model.startBlock(.maths)
        #expect(model.run?.plan.domains == [.maths])
    }

    @Test func aBlockStartedPastTheDaysTurnIsPlannedForTheNewDay() throws {
        let clock = TestClock()
        let model = TestApp.onboardedModel([.maths], clock: clock)
        clock.advance(86_400)
        model.startBlock(.maths)
        #expect(model.run?.plan.day == model.today)
        #expect(model.today == Day(clock.now, dayStartsAt: MindSettings.standardDayStart))
    }
}
