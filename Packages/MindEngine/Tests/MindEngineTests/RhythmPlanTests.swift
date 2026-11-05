import Foundation
import SystemCore
import Testing

@testable import MindEngine

/// Mind's week under the hub's rhythm: blocks fit around work, sleep and any change, and everything
/// Mind already does (the packed rule, rolling forward, Discipline) carries on.
@Suite("Mind with a rhythm")
struct RhythmPlanTests {
    let monday = Fixtures.monday.adding(weeks: 3)

    func nineToFive() -> Rhythm {
        let work = [DaySpan(.work, "Work", from: 540, to: 1020)]
        return Rhythm(pattern: WorkPattern(anchor: Fixtures.monday, weeks: [(0..<7).map { $0 < 5 ? work : [] }]), clearEvenings: 0)
    }

    func store(_ rhythm: Rhythm?, blocks: [Domain: Int] = [.japanese: 4, .reading: 3, .maths: 2, .writing: 1]) -> Store {
        var store = Store(settings: Fixtures.settings())
        store.weekSettings = WeekSettings(blocks: blocks, since: Fixtures.monday)
        store.rhythm = rhythm
        return store
    }

    func layout(_ store: Store, on day: Day) throws -> WeekLayout {
        WeekPlanner.layout(store.state(on: day), settings: try #require(store.weekSettings))
    }

    func block(_ domain: Domain, on day: Day) -> StudySession {
        let start = day.at(hour: 19, minute: 0)
        return StudySession(
            purpose: .regular, start: start, end: start.addingTimeInterval(1500), plannedMinutes: 25, domains: [domain], planned: true,
            activeSeconds: 1500, ranToEnd: true)
    }

    @Test func blocksNeverLandInWork() throws {
        let week = try layout(store(nineToFive()), on: monday)
        #expect(!week.blocks.isEmpty)
        // Work runs nine to five, so the morning has its hour first, and midday and afternoon nothing.
        for block in week.blocks where block.day.weekday.rawValue <= 5 {
            #expect(block.part != .midday && block.part != .afternoon, "\(block.id)")
        }
    }

    @Test func aRhythmReplacesDefaultsButNotTheDayJob() throws {
        // Someone who doesn't work on Tuesdays gets the day that Mind's defaults would have closed.
        var rhythm = nineToFive()
        rhythm.pattern?.weeks[0][1] = []
        let state = store(rhythm).state(on: monday)
        #expect(WeekPlanner.openParts(on: monday.adding(days: 1), state: state, settings: state.week).contains(.midday))
        #expect(!WeekPlanner.openParts(on: monday, state: state, settings: state.week).contains(.midday))
    }

    @Test func aPackedDayStaysPackedUnderARhythm() throws {
        var store = store(nineToFive())
        store.commitments = WeekCommitments(days: [
            .monday: [Commitment(title: "Lift", part: .early, minutes: 90), Commitment(title: "BJJ", part: .evening, minutes: 60)]
        ])
        #expect(try layout(store, on: monday).blocks(on: monday).isEmpty)
    }

    @Test func aClassStillClosesItsOwnPart() {
        var store = store(nineToFive())
        store.commitments = WeekCommitments(days: [.tuesday: [Commitment(title: "BJJ", part: .evening, minutes: 60)]])
        let state = store.state(on: monday)
        #expect(!WeekPlanner.openParts(on: monday.adding(days: 1), state: state, settings: state.week).contains(.evening))
    }

    @Test func alternateFridaysShowInTheWeek() throws {
        let work = [DaySpan(.work, "Work", from: 480, to: 1050)]
        let first = (0..<7).map { $0 < 5 ? work : [] }
        let second = (0..<7).map { $0 < 4 ? work : [] }
        let rhythm = Rhythm(pattern: WorkPattern(anchor: monday, weeks: [first, second]), clearEvenings: 0)
        let state = store(rhythm).state(on: monday)
        let friday = monday.adding(days: 4)
        #expect(!WeekPlanner.openParts(on: friday, state: state, settings: state.week).contains(.midday))
        #expect(WeekPlanner.openParts(on: friday.adding(weeks: 1), state: state, settings: state.week).contains(.midday))
    }

    @Test func pastTheEndOfTermItFallsBackOnTheDefaults() {
        var rhythm = nineToFive()
        rhythm.pattern?.endsOn = monday.adding(days: -1)
        let state = store(rhythm).state(on: monday)
        #expect(WeekPlanner.openParts(on: monday, state: state, settings: state.week) == [.early, .evening, .night])
    }

    // MARK: Changes

    @Test func outTonightMovesTonightsBlocks() throws {
        var store = store(nineToFive())
        let tuesday = monday.adding(days: 1)
        #expect(try !layout(store, on: tuesday).blocks(on: tuesday).filter { $0.part == .evening || $0.part == .night }.isEmpty)
        store.dayChanges = [DayChange.outTonight(on: tuesday)]
        let week = try layout(store, on: tuesday)
        #expect(week.blocks(on: tuesday).allSatisfy { $0.part != .evening && $0.part != .night })
        #expect(week.blocks.count == 10, "they went elsewhere in the week")
    }

    /// At four in the afternoon the morning is over, so that's no place for tonight's blocks.
    @Test func goingOutLateMovesBlocksToAnotherDayNotToAMorningThatsGone() throws {
        var store = store(nineToFive())
        let tuesday = monday.adding(days: 1)
        store.dayChanges = [DayChange.outTonight(on: tuesday, during: .afternoon)]
        let week = try layout(store, on: tuesday)
        #expect(week.blocks(on: tuesday).isEmpty)
    }

    @Test func outTonightWorksWithoutARhythm() throws {
        var store = store(nil)
        let tuesday = monday.adding(days: 1)
        store.dayChanges = [DayChange.outTonight(on: tuesday)]
        #expect(try layout(store, on: tuesday).blocks(on: tuesday).allSatisfy { $0.part != .evening && $0.part != .night })
    }

    @Test func aDoneBlockSurvivesOutTonight() throws {
        var store = store(nineToFive())
        let tuesday = monday.adding(days: 1)
        store.sessions = [block(.japanese, on: tuesday)]
        store.dayChanges = [DayChange.outTonight(on: tuesday)]
        let week = try layout(store, on: tuesday)
        #expect(week.done[.japanese] == 1)
        #expect(week.blocks.contains { $0.day == tuesday && $0.domain == .japanese && $0.done })
    }

    @Test func aLighterWeekHalvesTheBlocks() throws {
        var store = store(nineToFive())
        store.dayChanges = [DayChange.lighterWeek(of: monday)]
        #expect(try layout(store, on: monday).counts == [.japanese: 2, .reading: 2, .maths: 1, .writing: 1])
        #expect(try layout(store, on: monday.adding(weeks: 1)).counts[.japanese] == 4, "it ends on Sunday")
    }

    @Test func aLighterReviewWeekDoesntStack() throws {
        var store = store(nineToFive())
        store.calendar = SystemCalendar(currentBlock: nil, deloads: [DayRange(monday, monday.adding(days: 6))], checkIns: [], publishedBy: .liftTrack)
        store.dayChanges = [DayChange.lighterWeek(of: monday)]
        #expect(try layout(store, on: monday).counts[.japanese] == 2)
    }

    /// Lighter week tapped in the hub, and Mind never opened: its ledger still says the full week.
    @Test func aLighterWeekWithMindUnopenedInventsNoMisses() {
        var store = store(nineToFive(), blocks: [.japanese: 4])
        store.settings = Fixtures.settings([.japanese])
        store.weekSettings?.since = monday
        store.weekSettings?.record(WeekTarget(total: 4, counts: [.japanese: 4], days: 7), for: monday)
        store.dayChanges = [DayChange.lighterWeek(of: monday)]
        store.sessions = [block(.japanese, on: monday), block(.japanese, on: monday.adding(days: 1))]
        // The blocks alone: the days before `since` are scored under the old rule.
        let state = store.state(on: monday.adding(days: 8))
        let items = Analyst.blockItems(state, settings: state.week, window: Discipline.window(ending: state.today), exempt: [])
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.done == true })
    }

    @Test func aDeletedChangeDoesNothing() throws {
        var store = store(nineToFive())
        store.dayChanges = [DayChange.lighterWeek(of: monday).deleted()]
        #expect(try layout(store, on: monday).counts[.japanese] == 4)
    }

    @Test func theGridFollowsTheRhythm() throws {
        let store = store(nineToFive())
        let state = store.state(on: monday)
        let cells = WeekPlanner.cells(state, settings: state.week, layout: try layout(store, on: monday))
        #expect(!cells.contains { $0.weekday == .monday && $0.part == .midday && $0.isOpen })
        #expect(cells.contains { $0.weekday == .saturday && $0.part == .midday && $0.isOpen })
        #expect(WeekPlanner.followsRhythm(state))
        #expect(!WeekPlanner.followsRhythm(self.store(nil).state(on: monday)))
    }

    /// The hub lays out the same week from what Mind publishes, with a rhythm too.
    @Test func theHubStillAgreesUnderARhythm() throws {
        var store = store(nineToFive())
        store.settings.autoPrioritise = false
        store.dayChanges = [DayChange.outTonight(on: monday.adding(days: 2))]
        store.sessions = [block(.japanese, on: monday)]
        let state = store.state(on: monday.adding(days: 1))
        let mine = WeekPlanner.layout(state, settings: state.week)
        let ask = WeekPlanner.published(state, layout: mine)
        let theirs = BlockPlanner.layout(ask, today: state.today, firstPart: nil) {
            DayShape.openParts(on: $0, rhythm: nineToFive(), changes: store.dayChanges) ?? []
        }
        #expect(theirs.blocks.map(\.id) == mine.blocks.map(\.id))
        #expect(ask.planned.count == mine.blocks.filter { !$0.done }.count)
    }
}
