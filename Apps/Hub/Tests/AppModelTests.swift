import Foundation
import HubEngine
import SystemCore
import SystemStore
import Testing

@testable import Hub

/// The hub's own state: what it keeps, what it publishes, and that it settles.
@Suite("The hub's model")
@MainActor
struct AppModelTests {
    func nineToFive() -> WorkPattern { SchedulePreset.nineToFive.pattern(anchor: TestApp.monday) }

    func setUp(_ model: AppModel) { model.finishSetup(pattern: nineToFive(), wake: 6 * 60, bed: 22 * 60 + 30) }

    @Test func itStartsOutSetUpByNothing() {
        let model = TestApp.model()
        #expect(!model.onboarded)
        #expect(model.thisWeek == nil)
        #expect(model.shared.read(.rhythm) == nil)
    }

    @Test func settingUpPublishesTheRhythm() throws {
        let model = TestApp.model()
        setUp(model)
        #expect(model.onboarded)
        let published = try #require(model.shared.read(.rhythm))
        #expect(published.pattern == nineToFive())
        #expect(published == model.rhythm)
        #expect(model.thisWeek?.days.count == 7)
        #expect(model.shownDay?.day == model.today)
    }

    @Test func aRhythmFromAnotherDeviceArrivesThroughTheFile() throws {
        let shared = SharedContainer(directory: TestApp.folder())
        let store = TestApp.store()
        var rhythm = Rhythm(pattern: nineToFive())
        rhythm.updated = TestApp.wednesday.addingTimeInterval(-60)
        try shared.write(rhythm, to: .rhythm, by: .hub)
        let model = TestApp.model(shared: shared, store: store)
        #expect(model.onboarded)
        #expect(store.get(RhythmRecord.self, id: RhythmRecord.singletonID)?.rhythm.pattern == nineToFive())
    }

    @Test func theNewerRhythmWinsEitherWay() throws {
        let clock = TestClock()
        let shared = SharedContainer(directory: TestApp.folder())
        let store = TestApp.store()
        let model = TestApp.model(clock: clock, shared: shared, store: store)
        setUp(model)
        clock.advance(hours: 1)
        var newer = Rhythm(pattern: SchedulePreset.university.pattern(anchor: TestApp.monday))
        newer.updated = clock.now
        try shared.write(newer, to: .rhythm, by: .hub)
        model.readShared()
        #expect(model.rhythm?.pattern == newer.pattern)
        // And an older file loses to what's here, and is put right.
        var older = newer
        older.pattern = nineToFive()
        older.updated = clock.now.addingTimeInterval(-7200)
        try shared.write(older, to: .rhythm, by: .hub)
        model.readShared()
        #expect(model.rhythm?.pattern == newer.pattern)
        #expect(shared.read(.rhythm)?.pattern == newer.pattern)
    }

    /// A rhythm that didn't read back the same would write itself for ever, waking every app.
    @Test func readingAgainWritesNothing() throws {
        let model = TestApp.model()
        setUp(model)
        model.outTonight()
        let before = try #require(model.shared.envelope(.rhythm)?.writtenAt)
        let changes = try #require(model.shared.envelope(.dayChanges)?.writtenAt)
        model.readShared()
        model.readShared()
        #expect(model.shared.envelope(.rhythm)?.writtenAt == before)
        #expect(model.shared.envelope(.dayChanges)?.writtenAt == changes)
    }

    @Test func outTonightClosesTheEveningAndCanBeTakenBack() {
        let model = TestApp.model()
        setUp(model)
        model.outTonight()
        model.outTonight()
        #expect(model.isOutTonight)
        #expect(model.changes.count == 1, "twice is still once")
        #expect(model.shownDay?.parts.first { $0.part == .evening }?.isClosed == true)
        model.backToPlan()
        #expect(!model.isOutTonight)
        #expect(model.shownDay?.parts.first { $0.part == .evening }?.isClosed == false)
        // The tombstone is published, so the other apps let it go too.
        #expect(model.shared.read(.dayChanges)?.count == 1)
        #expect(model.shared.read(.dayChanges)?.live.isEmpty == true)
    }

    @Test func aLighterWeekEndsWithItsWeek() {
        let clock = TestClock()
        let model = TestApp.model(clock: clock)
        setUp(model)
        model.toggleLighterWeek()
        #expect(model.isLighter)
        clock.advance(days: 5)
        model.tick()
        #expect(model.today.startOfWeek != TestApp.monday)
        #expect(!model.isLighter)
    }

    @Test func goingBackLeavesWhatsAlreadyPassed() {
        let clock = TestClock()
        let model = TestApp.model(clock: clock)
        setUp(model)
        model.outTonight()
        clock.advance(days: 1)
        model.tick()
        model.toggleLighterWeek()
        model.backToPlan()
        #expect(!model.isLighter)
        #expect(model.changes.map(\.kind) == [DayChange.out], "last night stays where it was")
    }

    @Test func aChangeFromAnotherDeviceMergesIn() throws {
        let shared = SharedContainer(directory: TestApp.folder())
        let store = TestApp.store()
        let model = TestApp.model(shared: shared, store: store)
        setUp(model)
        try shared.write([DayChange.lighterWeek(of: model.today, at: TestApp.wednesday)], to: .dayChanges, by: .hub)
        model.outTonight()
        #expect(model.isLighter)
        #expect(model.isOutTonight)
        #expect(store.all(DayChangeRecord.self).count == 2)
    }

    @Test func oldChangesGo() throws {
        let clock = TestClock()
        let model = TestApp.model(clock: clock)
        setUp(model)
        model.outTonight()
        clock.advance(days: DayChange.keptDays + 2)
        model.tick()
        #expect(model.shared.read(.dayChanges)?.isEmpty == true)
        #expect(model.store.all(DayChangeRecord.self).isEmpty)
    }

    @Test func theSelectedDayFollowsTodayUnlessYouMovedIt() {
        let clock = TestClock()
        let model = TestApp.model(clock: clock)
        setUp(model)
        clock.advance(days: 1)
        model.tick()
        #expect(model.selectedDay == model.today)
        let friday = model.today.adding(days: 1)
        model.selectedDay = friday
        clock.advance(days: 1)
        model.tick()
        #expect(model.selectedDay == friday)
    }

    @Test func nothingFromTheAppsStillShowsTheDay() {
        let model = TestApp.model()
        setUp(model)
        #expect(model.lines.isEmpty)
        let day = model.shownDay
        #expect(day?.items.allSatisfy { $0.kind == .work } == true)
        #expect(day.flatMap { HubPlanner.next(in: $0, at: model.part) } == nil)
    }

    @Test func whatTheAppsPublishShowsUp() throws {
        let shared = SharedContainer(directory: TestApp.folder())
        let model = TestApp.model(shared: shared)
        setUp(model)
        try shared.write(SampleData.ask(model.today.startOfWeek, now: TestApp.wednesday), to: .blockAsk, by: .knowledge)
        model.readShared()
        #expect(model.thisWeek?.study ?? 0 > 0)
        #expect(model.lines.map(\.label) == ["Study"])
    }

    @Test func theDayStartsWhenTheRhythmSays() {
        // Half past one in the morning is still yesterday.
        let clock = TestClock(Day(year: 2026, month: 10, day: 15).date().addingTimeInterval(1.5 * 3600))
        let model = TestApp.model(clock: clock)
        setUp(model)
        #expect(model.today == Day(year: 2026, month: 10, day: 14))
        #expect(model.part == .night)
    }
}
