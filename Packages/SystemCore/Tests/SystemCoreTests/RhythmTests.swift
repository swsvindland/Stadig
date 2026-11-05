import Foundation
import Testing

@testable import SystemCore

/// Real weeks, written the way a person's schedule would be, and what each leaves open.
@Suite("Rhythm")
struct RhythmTests {
    let monday = Day(year: 2026, month: 11, day: 2)
    func at(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }
    func days(_ week: [DaySpan], _ pattern: [Int] = [0, 1, 2, 3, 4]) -> [[DaySpan]] { (0..<7).map { pattern.contains($0) ? week : [] } }
    func rhythm(_ weeks: [[[DaySpan]]], clear: Int = 0) -> Rhythm {
        Rhythm(pattern: WorkPattern(anchor: monday, weeks: weeks), wake: at(5, 45), bed: at(22, 30), clearEvenings: clear)
    }
    func open(_ rhythm: Rhythm, _ day: Day, changes: [DayChange] = []) -> [DayPart]? { DayShape.openParts(on: day, rhythm: rhythm, changes: changes) }

    let nineToFive = [
        DaySpan(.commute, "Commute", from: 510, to: 540), DaySpan(.work, "Work", from: 540, to: 1020),
        DaySpan(.commute, "Commute", from: 1020, to: 1050),
    ]

    @Test func anOfficeDayLeavesTheEndsOfTheDay() {
        // Office nine to half past three, the drive either side, then an hour at home.
        let office = [
            DaySpan(.commute, "Commute", from: at(8, 30), to: at(9)), DaySpan(.work, "Office", from: at(9), to: at(15, 30)),
            DaySpan(.commute, "Commute", from: at(15, 30), to: at(16)), DaySpan(.work, "At home", from: at(16), to: at(17)),
        ]
        let week = rhythm([days(office, [0, 1, 2, 3])])
        #expect(open(week, monday.adding(days: 1)) == [.early, .evening, .night])
    }

    @Test func aNineToFiveHasItsWeekendsFree() {
        let week = rhythm([days(nineToFive)])
        #expect(open(week, monday) == [.early, .evening, .night])
        #expect(open(week, monday.adding(days: 5)) == DayPart.allCases)
    }

    /// 9 hours Monday to Thursday, and every other Friday off.
    @Test func alternateFridaysComeAndGo() {
        let long = [DaySpan(.work, "Work", from: at(8), to: at(17, 30))]
        let first = (0..<7).map { $0 < 4 ? long : ($0 == 4 ? nineToFive : []) }
        let second = (0..<7).map { $0 < 4 ? long : [] }
        let week = rhythm([first, second])
        let friday = monday.adding(days: 4)
        #expect(open(week, friday)?.contains(.midday) == false)
        #expect(open(week, friday.adding(weeks: 1))?.contains(.midday) == true)
        #expect(open(week, friday.adding(weeks: 2))?.contains(.midday) == false)
        // Before the anchor it still lands on the right Friday.
        #expect(open(week, friday.adding(weeks: -1))?.contains(.midday) == true)
    }

    @Test func pastTheEndOfTermNothingIsKnown() {
        var pattern = WorkPattern(anchor: monday, weeks: [days([DaySpan(.school, "Lecture", from: at(10), to: at(12))])])
        pattern.endsOn = monday.adding(days: 11)
        let term = Rhythm(pattern: pattern, clearEvenings: 0)
        #expect(open(term, monday.adding(days: 11))?.contains(.morning) == true)
        #expect(open(term, monday.adding(days: 12)) == nil)
    }

    @Test func aRosterDayWithNoEntryIsNotFree() {
        var pattern = WorkPattern(anchor: monday, weeks: [], isRoster: true)
        pattern.overrides[monday.iso] = [DaySpan(.work, "Shift", from: at(6), to: at(14))]
        let roster = Rhythm(pattern: pattern, clearEvenings: 0)
        #expect(open(roster, monday)?.contains(.morning) == false)
        #expect(open(roster, monday.adding(days: 1)) == nil)
    }

    /// Ten at night to six in the morning, asleep from half past six until two.
    @Test func aNightShiftRunsIntoTheNextDay() {
        let night = [DaySpan(.work, "Night shift", from: at(22), to: at(30)), DaySpan(.sleep, "Sleep", from: at(6, 30), to: at(14))]
        let week = rhythm([days(night, [1, 2, 3])])
        let wednesday = monday.adding(days: 2)
        let parts = open(week, wednesday)
        #expect(parts?.contains(.early) == false, "still on last night's shift")
        #expect(parts?.contains(.morning) == false, "asleep")
        #expect(parts?.contains(.afternoon) == true)
        #expect(parts?.contains(.evening) == true)
        #expect(parts?.contains(.night) == true, "two hours before tonight's shift")
        let thursday = rhythm([days([DaySpan(.work, "Night shift", from: at(20, 30), to: at(29))], [3])])
        #expect(open(thursday, monday.adding(days: 3))?.contains(.night) == false, "half an hour isn't enough")
    }

    @Test func aDayWithNothingOnStillSleeps() {
        let week = rhythm([days([])])
        #expect(open(week, monday.adding(days: 5)) == DayPart.allCases)
        let late = Rhythm(pattern: WorkPattern(anchor: monday, weeks: [days([])]), wake: at(9), bed: at(20, 30), clearEvenings: 0)
        #expect(open(late, monday)?.contains(.early) == false)
        #expect(open(late, monday)?.contains(.night) == false)
    }

    @Test func aShortGapDoesntCount() {
        let split = [DaySpan(.work, "Work", from: at(8), to: at(9, 20)), DaySpan(.work, "Work", from: at(10), to: at(11))]
        #expect(open(rhythm([days(split)]), monday)?.contains(.morning) == false, "40 minutes free")
        let wider = [DaySpan(.work, "Work", from: at(8), to: at(9, 15)), DaySpan(.work, "Work", from: at(10), to: at(11))]
        #expect(open(rhythm([days(wider)]), monday)?.contains(.morning) == true, "45 minutes free")
    }

    // MARK: Clear evenings

    @Test func theEndOfTheWeeksEveningsStayClear() {
        let week = rhythm([days(nineToFive)], clear: 2)
        #expect(DayShape.clearEvenings(weekOf: monday, rhythm: week) == [monday.adding(days: 4), monday.adding(days: 5)])
        #expect(open(week, monday.adding(days: 4)) == [.early])
        #expect(open(week, monday.adding(days: 5))?.contains(.evening) == false)
        #expect(open(week, monday)?.contains(.evening) == true)
    }

    @Test func anEveningAtWorkIsntOneToKeep() {
        let late = [DaySpan(.work, "Late shift", from: at(14), to: at(23))]
        let week = rhythm([days(late, [4, 5])], clear: 1)
        #expect(DayShape.clearEvenings(weekOf: monday, rhythm: week) == [monday.adding(days: 6)])
    }

    // MARK: Changes

    @Test func outTonightClearsTheEveningAndNight() {
        let week = rhythm([days(nineToFive)])
        let change = DayChange.outTonight(on: monday)
        #expect(open(week, monday, changes: [change]) == [.early])
        #expect(open(week, monday.adding(days: 1), changes: [change])?.contains(.evening) == true)
        #expect(open(week, monday, changes: [change.deleted()])?.contains(.evening) == true)
    }

    @Test func aLighterWeekIsTheWholeWeek() {
        let changes = [DayChange.lighterWeek(of: monday.adding(days: 3))]
        #expect(changes.isLighter(monday))
        #expect(changes.isLighter(monday.adding(days: 6)))
        #expect(!changes.isLighter(monday.adding(days: 7)))
    }

    @Test func aDeviceBehindCantUndoAChange() {
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let change = DayChange.outTonight(on: monday, at: t0)
        let undone = change.deleted(at: t0.addingTimeInterval(60))
        for sources in [[[undone], [change]], [[change], [undone]]] { #expect(DayChange.merge(sources) == [undone]) }
        let other = DayChange.lighterWeek(of: monday, at: t0)
        #expect(Set(DayChange.merge([[change], [other]])) == [change, other], "one device's change doesn't wipe out another's")
    }

    @Test func oldChangesAreForgotten() {
        let old = DayChange.outTonight(on: monday)
        #expect([old].kept(on: monday.adding(days: 42)) == [old])
        #expect([old].kept(on: monday.adding(days: 43)).isEmpty)
    }

    @Test func aLighterSessionIsShorterButWorthTheTrip() {
        #expect(DayChange.lighterMinutes(90) == 60)
        #expect(DayChange.lighterMinutes(60) == 40)
        #expect(DayChange.lighterMinutes(35) == 30)
    }

    // MARK: Files

    @Test func aChangeOfAKindFromANewerBuildDoesntFailTheList() throws {
        let json = #"[{"id":"00000000-0000-0000-0000-000000000001","kind":"sabbatical","day":"2026-11-02","parts":[],"updatedAt":0}]"#
        let decoder = JSONDecoder()
        let changes = try decoder.decode([DayChange].self, from: Data(json.utf8))
        #expect(changes.count == 1)
        #expect(changes.closedParts(on: monday).isEmpty)
        #expect(!changes.isLighter(monday))
    }

    @Test func aSpanOfAKindFromANewerBuildCountsAsBusy() throws {
        let span = try JSONDecoder().decode(DaySpan.self, from: Data(#"{"kind":"caring","label":"Mum","start":540,"end":600}"#.utf8))
        #expect(span.kind == .work)
    }

    @Test func aRhythmFromNothingHasItsDefaults() throws {
        let rhythm = try JSONDecoder().decode(Rhythm.self, from: Data("{}".utf8))
        #expect(rhythm.clearEvenings == Rhythm.standardClearEvenings)
        #expect(rhythm.pattern == nil)
        #expect(DayShape.openParts(on: monday, rhythm: rhythm, changes: []) == nil, "no pattern: the app keeps its own defaults")
    }

    @Test func flexibleThingsGoInThePartsLongestStretch() {
        // Up at six, out of the door at half past seven: the early part's room starts at six.
        #expect(DayShape.longestRunStart(.early, busy: [(0, 360), (450, 480)]) == 360)
        // Home at six: the evening's room starts then.
        #expect(DayShape.longestRunStart(.evening, busy: [(1020, 1080)]) == 1080)
        #expect(DayShape.longestRunStart(.morning, busy: []) == DayPart.morning.minutes.lowerBound)
    }

    @Test func goingOutLateAlsoClosesWhatsAlreadyGone() {
        let day = Day(year: 2026, month: 11, day: 5)
        #expect(DayChange.outTonight(on: day).parts == ["evening", "night"])
        #expect(DayChange.outTonight(on: day, during: .morning).parts == ["early", "evening", "night"])
        // The part it is now stays open: there may be time yet.
        #expect(DayChange.outTonight(on: day, during: .afternoon).parts == ["early", "morning", "midday", "evening", "night"])
        #expect(DayChange.outTonight(on: day, during: .night).parts == DayPart.allCases.map(\.rawValue))
    }
}
