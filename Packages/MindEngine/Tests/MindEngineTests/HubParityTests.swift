import Foundation
import SystemCore
import Testing

@testable import MindEngine

/// The hub lays out Stadig Mind's week without Mind running, from what Mind last published. That only
/// works if the two agree, so this is the check everything else rests on: what the hub would show
/// from an ask of any age up to a week against what Mind itself would lay out on that day, when
/// nothing has been studied in between.
@Suite("The hub and Stadig Mind agree")
struct HubParityTests {
    let start = Fixtures.monday

    func busyWeek() -> WeekCommitments {
        let lift = Commitment(title: "Lift", part: .early, minutes: 90)
        let bjj = Commitment(title: "BJJ", part: .evening, minutes: 60)
        return WeekCommitments(days: [.monday: [lift, bjj], .wednesday: [lift, bjj], .friday: [lift]])
    }

    func block(_ domain: Domain, on day: Day, part: DayPart) -> StudySession {
        let start = day.at(minutes: part.minutes.lowerBound + 10)
        return StudySession(
            purpose: .regular, start: start, end: start.addingTimeInterval(1500), plannedMinutes: 25, domains: [domain], planned: true,
            activeSeconds: 1500, ranToEnd: true)
    }

    func hub(_ ask: BlockAsk, on day: Day, _ state: StudyState) -> BlockLayout {
        BlockPlanner.layout(ask, today: day, firstPart: DayPart(hour: 18)) {
            WeekPlanner.openParts($0.weekday, commitments: state.commitments, settings: state.week)
        }
    }

    /// Runs a person through twelve weeks, keeping about two blocks in three, with a pause and two
    /// review weeks that don't start on a Monday, and compares every day from every age of ask.
    @Test func twelveWeeksMatchFromAskUpToAWeekOld() throws {
        var settings = Fixtures.settings()
        settings.autoPrioritise = false
        var store = Store(settings: settings)
        store.weekSettings = WeekSettings(blocks: [.japanese: 4, .reading: 3, .maths: 2, .writing: 1], since: start)
        store.commitments = busyWeek()
        store.lifeModes = [LifeModePeriod(kind: .vacation, start: start.adding(days: 30), end: start.adding(days: 36), createdBy: .knowledge)]
        store.calendar = SystemCalendar(
            currentBlock: nil,
            deloads: [DayRange(start.adding(days: 45), start.adding(days: 51)), DayRange(start.adding(days: 73), start.adding(days: 79))],
            checkIns: [], publishedBy: .liftTrack)
        var rng = SeededRandom(seed: 7)
        var compared = 0
        var mismatches: [String] = []

        for offset in 0..<84 {
            let day = start.adding(days: offset)
            let published = store.state(on: day)
            let week = published.week
            let ask = WeekPlanner.ask(published, settings: week, monday: day.startOfWeek, lagging: [])
            for age in [0, 1, 3, 7] {
                let later = day.adding(days: age)
                let state = store.state(on: later)
                let mine = WeekPlanner.layout(state, settings: week)
                let theirs = hub(ask, on: later, state)
                compared += 1
                let same =
                    mine.blocks.map(\.id) == theirs.blocks.map(\.id)
                    && mine.leftovers.map { ($0.key.rawValue, $0.value) }.sorted { $0.0 < $1.0 }.map(\.1)
                        == theirs.leftovers.sorted { $0.key < $1.key }.map(\.value)
                if !same { mismatches.append("\(day.iso) +\(age)") }
            }
            for block in WeekPlanner.layout(published, settings: week).blocks(on: day) where !block.done && rng.chance(0.66) {
                store.sessions.append(self.block(block.domain, on: day, part: block.part))
            }
        }
        #expect(compared == 336)
        #expect(mismatches.isEmpty, "\(mismatches.count) of \(compared): \(mismatches.prefix(12))")
        #expect(store.sessions.count > 40)
    }

    /// Asks published Sunday night are read on Monday, when nobody has opened Mind yet.
    @Test func aNewWeekWorksFromLastWeeksAsk() throws {
        var settings = Fixtures.settings()
        settings.autoPrioritise = false
        var store = Store(settings: settings)
        store.weekSettings = WeekSettings(blocks: [.japanese: 4, .reading: 3], since: start)
        let sunday = start.adding(days: 6)
        let state = store.state(on: sunday)
        let ask = WeekPlanner.ask(state, settings: state.week, monday: sunday.startOfWeek, lagging: [])
        let monday = sunday.adding(days: 1)
        let theirs = hub(ask, on: monday, store.state(on: monday))
        #expect(theirs.counts == ["japanese": 4, "reading": 3, "maths": 0, "writing": 0])
        store.sessions = []
        #expect(theirs.blocks.map(\.id) == WeekPlanner.layout(store.state(on: monday), settings: state.week).blocks.map(\.id))
    }

    /// A lagging course's extra block is for the week it was published in, so it's the one thing the
    /// hub can be a block out on next week until Mind has run.
    @Test func anExtraBlockDoesntCarryIntoNextWeek() {
        let store = { () -> Store in
            var store = Store(settings: Fixtures.settings())
            store.weekSettings = WeekSettings(blocks: [.japanese: 2], since: start)
            return store
        }()
        let state = store.state(on: start)
        let ask = WeekPlanner.ask(state, settings: state.week, monday: start, lagging: [.japanese])
        let course = ask.courses.first { $0.id == "japanese" }!
        #expect(ask.count(course, monday: start) == 3)
        #expect(ask.count(course, monday: start.adding(weeks: 1)) == 2)
    }
}
