import Foundation
import SystemCore
import Testing

@testable import MindEngine

@Suite("Week planner")
struct WeekPlannerTests {
    /// Past the two weeks of assessment, so a calendar's deloads apply.
    let monday = Fixtures.monday.adding(weeks: 3)

    /// A week like the one this was built for: lifting early on Monday, Wednesday and Friday, and
    /// BJJ and Muay Thai on Monday and Wednesday evenings.
    let busyWeek = WeekCommitments(days: [
        .monday: [
            Commitment(title: "Lift", part: .early, minutes: 90), Commitment(title: "BJJ", part: .evening, minutes: 60),
            Commitment(title: "Muay Thai", part: .evening, minutes: 60),
        ],
        .wednesday: [
            Commitment(title: "Lift", part: .early, minutes: 90), Commitment(title: "BJJ", part: .evening, minutes: 60),
            Commitment(title: "Muay Thai", part: .evening, minutes: 60),
        ],
        .friday: [Commitment(title: "Lift", part: .early, minutes: 90)],
    ])

    func store(_ blocks: [Domain: Int] = [.japanese: 4, .reading: 4, .maths: 2, .writing: 1], commitments: WeekCommitments = .none) -> Store {
        var store = Store(settings: Fixtures.settings())
        store.weekSettings = WeekSettings(blocks: blocks, since: Fixtures.monday)
        store.commitments = commitments
        return store
    }

    func block(_ domain: Domain, on day: Day, hour: Int = 19, finished: Bool = true) -> StudySession {
        let start = day.at(hour: hour, minute: 0)
        return StudySession(
            purpose: .regular, start: start, end: start.addingTimeInterval(1500), plannedMinutes: 25, domains: [domain], planned: true,
            activeSeconds: finished ? 1500 : 120, ranToEnd: finished)
    }

    func layout(_ store: Store, on day: Day) throws -> WeekLayout {
        WeekPlanner.layout(store.state(on: day), settings: try #require(store.weekSettings))
    }

    // MARK: Open parts

    @Test func weekdaysOfferTheEndsOfTheDayAndWeekendsAllOfIt() {
        let week = WeekSettings(since: monday)
        #expect(WeekPlanner.openParts(.tuesday, commitments: .none, settings: week) == [.early, .evening, .night])
        #expect(WeekPlanner.openParts(.saturday, commitments: .none, settings: week) == DayPart.allCases)
    }

    @Test func oneCommitmentClosesItsOwnPart() {
        let week = WeekSettings(since: monday)
        #expect(WeekPlanner.openParts(.friday, commitments: busyWeek, settings: week) == [.evening, .night])
    }

    @Test func aPackedDayIsClosed() {
        let week = WeekSettings(since: monday)
        #expect(WeekPlanner.isPacked(.monday, commitments: busyWeek))
        #expect(!WeekPlanner.isPacked(.friday, commitments: busyWeek))
        #expect(WeekPlanner.openParts(.monday, commitments: busyWeek, settings: week).isEmpty)
    }

    @Test func anyPartCanBeOpenedOrClosedByHand() {
        var week = WeekSettings(since: monday)
        week.setOverride(true, .monday, .night)
        week.setOverride(true, .tuesday, .midday)
        week.setOverride(false, .tuesday, .night)
        #expect(WeekPlanner.openParts(.monday, commitments: busyWeek, settings: week) == [.night])
        #expect(WeekPlanner.openParts(.tuesday, commitments: busyWeek, settings: week) == [.early, .midday, .evening])
    }

    @Test func theGridShowsEachPartOfTheWeek() {
        let store = store(commitments: busyWeek)
        let layout = WeekPlanner.layout(store.state(on: monday), settings: store.weekSettings!)
        let cells = WeekPlanner.cells(settings: store.weekSettings!, commitments: busyWeek, layout: layout)
        #expect(cells.count == 42)
        let early = cells.first { $0.weekday == .monday && $0.part == .early }
        #expect(early?.content == .commitment(title: "Lift", symbol: "figure.strengthtraining.traditional"))
        #expect(early?.isOpen == false)
        #expect(cells.first { $0.weekday == .monday && $0.part == .night }?.content == .closed)
        #expect(cells.contains { if case .block(.japanese, _) = $0.content { $0.part == .night } else { false } })
        #expect(early?.accessibilityLabel == "Monday early: Lift")
    }

    @Test func tappingFlipsAPartAndTappingBackForgetsIt() throws {
        let week = try #require(store(commitments: busyWeek).weekSettings)
        let opened = WeekPlanner.toggling(.monday, .night, settings: week, commitments: busyWeek)
        #expect(WeekPlanner.openParts(.monday, commitments: busyWeek, settings: opened) == [.night])
        let back = WeekPlanner.toggling(.monday, .night, settings: opened, commitments: busyWeek)
        #expect(back.parts.isEmpty)
    }

    // MARK: The week this was built for

    @Test func packedDaysGetNoBlocksAndEveryBlockLandsElsewhere() throws {
        let store = store(commitments: busyWeek)
        let week = try layout(store, on: monday)
        #expect(week.blocks(on: monday).isEmpty)
        #expect(week.blocks(on: monday.adding(days: 2)).isEmpty)
        #expect(week.blocks.count == 11)
        #expect(week.leftoverCount == 0)
        #expect(week.counts == [.japanese: 4, .reading: 4, .maths: 2, .writing: 1])
        for (domain, count) in week.counts { #expect(week.blocks.filter { $0.domain == domain }.count == count) }
    }

    @Test func aCourseGetsOneBlockADayWhileThereAreDays() throws {
        let week = try layout(store(commitments: busyWeek), on: monday)
        for domain in Domain.allCases {
            let days = week.blocks.filter { $0.domain == domain }.map(\.day)
            #expect(Set(days).count == days.count, "\(domain) twice in a day")
        }
    }

    @Test func coursesLeanTowardsTheirTimeOfDay() throws {
        let week = try layout(store(commitments: busyWeek), on: monday)
        #expect(week.blocks.filter { $0.domain == .maths }.allSatisfy { $0.part == .morning })
        #expect(week.blocks.filter { $0.domain == .japanese }.allSatisfy { $0.part == .night })
    }

    @Test func aPinBeatsTheUsualFit() throws {
        var store = store()
        store.weekSettings?.setPin(.night, for: .maths)
        let week = try layout(store, on: monday)
        #expect(week.blocks.filter { $0.domain == .maths }.allSatisfy { $0.part == .night })
    }

    @Test func theSameWeekAlwaysComesOutTheSame() throws {
        let store = store(commitments: busyWeek)
        #expect(try layout(store, on: monday) == layout(store, on: monday))
    }

    // MARK: Counts

    @Test func aThursdayStartAsksForAShareOfTheWeek() throws {
        var store = store()
        store.weekSettings?.since = monday.adding(days: 3)
        let week = try layout(store, on: monday.adding(days: 3))
        // Four days of seven, rounded up.
        #expect(week.counts[.japanese] == 3)
        #expect(week.counts[.writing] == 1)
        #expect(week.blocks.allSatisfy { $0.day >= monday.adding(days: 3) })
    }

    @Test func aPauseEndingWednesdayAsksForAShareOfTheWeek() throws {
        var store = store()
        store.lifeModes = [LifeModePeriod(kind: .vacation, start: monday.adding(days: -3), end: monday.adding(days: 2), createdBy: .knowledge)]
        let week = try layout(store, on: monday)
        #expect(week.counts[.japanese] == 3)
        #expect(week.blocks.allSatisfy { $0.day > monday.adding(days: 2) })
    }

    @Test func aReviewWeekHalvesTheBlocksRoundingUp() throws {
        var store = store()
        store.calendar = SystemCalendar(currentBlock: nil, deloads: [DayRange(monday, monday.adding(days: 6))], checkIns: [], publishedBy: .liftTrack)
        let week = try layout(store, on: monday)
        #expect(week.counts == [.japanese: 2, .reading: 2, .maths: 1, .writing: 1])
    }

    /// Review weeks follow Stadig Lift's deloads, which needn't start on a Monday.
    @Test func aReviewWeekStartingMidweekHalvesOnlyItsOwnDays() throws {
        var store = store()
        store.calendar = SystemCalendar(
            currentBlock: nil, deloads: [DayRange(monday.adding(days: 2), monday.adding(days: 8))], checkIns: [], publishedBy: .liftTrack)
        let week = try layout(store, on: monday)
        // Two whole days and five at half: 4 × 4.5 / 7 is 2.6, rounded up.
        #expect(week.counts[.japanese] == 3)
    }

    @Test func aLaggingCourseGetsOneMoreBlockFixedOnMonday() throws {
        var store = store()
        var state = store.state(on: monday.adding(days: 2))
        state.recommendations = [
            Recommendation(
                from: .hub, to: .knowledge, kind: .prioritise, subject: .stat(.wisdom), reason: "", created: monday.adding(days: -2).date())
        ]
        let week = WeekPlanner.layout(state, settings: try #require(store.weekSettings))
        #expect(week.counts[.reading] == 5)
        store.settings.autoPrioritise = false
        state.settings = store.settings
        #expect(WeekPlanner.layout(state, settings: try #require(store.weekSettings)).counts[.reading] == 4)
    }

    // MARK: Rolling forward

    @Test func aMissedBlockRollsForward() throws {
        var store = store()
        store.sessions = [block(.japanese, on: monday)]
        // Nothing happened on Tuesday. Wednesday's week still holds the other three.
        let week = try layout(store, on: monday.adding(days: 2))
        #expect(week.blocks.filter { $0.domain == .japanese && !$0.done }.count == 3)
        #expect(week.blocks.filter { !$0.done }.allSatisfy { $0.day >= monday.adding(days: 2) })
    }

    @Test func studyOnAClosedDayCountsTowardsTheWeek() throws {
        var store = store(commitments: busyWeek)
        store.sessions = [block(.japanese, on: monday)]
        let week = try layout(store, on: monday.adding(days: 1))
        #expect(week.done[.japanese] == 1)
        #expect(week.blocks.filter { $0.domain == .japanese && !$0.done }.count == 3)
    }

    @Test func aBlockStudiedOffPlanCountsEvenWhenNotMarkedPlanned() throws {
        var store = store()
        var session = block(.japanese, on: monday)
        session.planned = false
        store.sessions = [session]
        #expect(try layout(store, on: monday.adding(days: 1)).done[.japanese] == 1)
    }

    @Test func aSessionStoppedEarlyLeavesItsBlockToDo() throws {
        var store = store()
        store.sessions = [block(.japanese, on: monday, finished: false)]
        let week = try layout(store, on: monday.adding(days: 1))
        #expect(week.done[.japanese] == nil)
        #expect(week.blocks.filter { $0.domain == .japanese && !$0.done }.count == 4)
    }

    @Test func checkInsAndQuickReviewsAreNotBlocks() throws {
        var store = store()
        var checkIn = block(.japanese, on: monday)
        checkIn.purpose = .checkIn
        var extra = block(.japanese, on: monday)
        extra.purpose = .extra
        store.sessions = [checkIn, extra]
        #expect(try layout(store, on: monday.adding(days: 1)).done[.japanese] == nil)
    }

    @Test func aLastWeeksBlockDoesntCount() throws {
        var store = store()
        store.sessions = [block(.japanese, on: monday.adding(days: -1))]
        #expect(try layout(store, on: monday).done[.japanese] == nil)
    }

    /// With days starting at 4 a.m., a block at 1 a.m. Saturday belongs to Friday.
    @Test func aBlockAfterMidnightBelongsToTheDayBefore() throws {
        var store = store()
        store.settings.dayStart = 4
        let saturday = monday.adding(days: 5)
        store.sessions = [block(.japanese, on: saturday, hour: 1)]
        let week = try layout(store, on: saturday)
        let done = try #require(week.blocks.first { $0.done })
        #expect(done.day == monday.adding(days: 4))
    }

    // MARK: Holding through the day

    @Test func todaysListHoldsAsItsBlocksGetDone() throws {
        var store = store()
        let tuesday = monday.adding(days: 1)
        let before = try layout(store, on: tuesday).blocks(on: tuesday)
        let first = try #require(before.first)
        store.sessions = [block(first.domain, on: tuesday)]
        let after = try layout(store, on: tuesday).blocks(on: tuesday)
        #expect(after.map(\.id) == before.map(\.id))
        #expect(after.filter(\.done).map(\.domain) == [first.domain])
    }

    /// A finished block mustn't count against today's own parts: it would push its course off the day
    /// and pull others on.
    @Test func noDaysListChangesAsItsBlocksGetDone() throws {
        for offset in 0..<7 {
            let day = monday.adding(days: offset)
            var store = store([.japanese: 4, .reading: 3, .maths: 2, .writing: 1])
            let before = try layout(store, on: day).blocks(on: day)
            for (index, block) in before.enumerated() {
                store.sessions.append(self.block(block.domain, on: day))
                let after = try layout(store, on: day).blocks(on: day)
                #expect(after.map(\.id) == before.map(\.id), "\(day) after \(index + 1)")
                #expect(after.filter(\.done).count == index + 1)
            }
        }
    }

    @Test func aPlacementLeftWithoutAnAnswerIsStillToDo() throws {
        var store = store()
        let start = monday.at(hour: 19, minute: 0)
        store.sessions = [
            StudySession(purpose: .placement, start: start, end: start.addingTimeInterval(4), plannedMinutes: 10, domains: [.maths], planned: true)
        ]
        #expect(try layout(store, on: monday.adding(days: 1)).done[.maths] == nil)
    }

    @Test func twoOfACourseInOnePartHaveTheirOwnIDs() throws {
        var store = store()
        store.sessions = [block(.japanese, on: monday), StudySession.conversation(.japanese, at: monday.at(hour: 19, minute: 30))]
        let ids = try layout(store, on: monday.adding(days: 1)).blocks.map(\.id)
        #expect(Set(ids).count == ids.count, "\(ids)")
    }

    /// Set up on a Sunday with Sunday closed: the first block still follows.
    @Test func theFirstBlockFollowsEvenWithNoPartsLeftInTheWeek() throws {
        let sunday = monday.adding(days: 6)
        var store = store([.japanese: 4])
        store.weekSettings?.since = sunday
        for part in DayPart.allCases { store.weekSettings?.setOverride(false, .sunday, part) }
        let week = try layout(store, on: sunday)
        #expect(week.blocks(on: sunday).map(\.domain) == [.japanese])
        #expect(week.leftoverCount == 0)
    }

    /// Setup's preview shows the week, with nothing on a packed day.
    @Test func thePreviewOfAPackedMondayIsEmpty() throws {
        let store = store(commitments: busyWeek)
        let cells = WeekPlanner.preview(store.settings, week: try #require(store.weekSettings), commitments: busyWeek, on: monday)
        let blocks = cells.filter { if case .block = $0.content { true } else { false } }
        #expect(blocks.count == 11)
        #expect(!blocks.contains { $0.weekday == .monday || $0.weekday == .wednesday })
    }

    @Test func aBlockTodayThatWasntPlannedComesOffTheEndOfTheWeek() throws {
        var store = store()
        let tuesday = monday.adding(days: 1)
        let before = try layout(store, on: tuesday)
        let today = Set(before.blocks(on: tuesday).map(\.domain))
        let other = try #require(Domain.allCases.first { !today.contains($0) && before.counts[$0, default: 0] > 0 })
        store.sessions = [block(other, on: tuesday, hour: 12)]
        let after = try layout(store, on: tuesday)
        #expect(Set(after.blocks(on: tuesday).filter { !$0.done }.map(\.domain)) == today)
        #expect(after.blocks.filter { $0.domain == other && !$0.done }.count == before.blocks.filter { $0.domain == other }.count - 1)
        #expect(after.blocks.contains { $0.day == tuesday && $0.domain == other && $0.done })
    }

    // MARK: When it doesn't fit

    @Test func whatDoesntFitIsLeftOverAndTheTargetIsWhatFits() throws {
        var store = store([.japanese: 7, .reading: 7, .maths: 7, .writing: 7], commitments: busyWeek)
        store.weekSettings?.setOverride(false, .saturday, .early)
        let week = try layout(store, on: monday)
        let open = Weekday.allCases.map { WeekPlanner.openParts($0, commitments: busyWeek, settings: store.weekSettings!).count }.reduce(0, +)
        #expect(week.blocks.count == open)
        #expect(week.leftoverCount == 28 - open)
        #expect(week.target == open)
    }

    @Test func theTargetCountsBlocksDoneOnClosedDays() throws {
        var store = store([.japanese: 1])
        store.sessions = [block(.japanese, on: monday)]
        #expect(try layout(store, on: monday.adding(days: 1)).target == 1)
    }

    @Test func aCourseWithNoBlocksGetsNone() throws {
        let week = try layout(store([.japanese: 2]), on: monday)
        #expect(week.blocks.allSatisfy { $0.domain == .japanese })
    }
}
