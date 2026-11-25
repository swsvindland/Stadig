import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// The weekly check-in lands on a Monday, and the plan is looked at with it: a rule that holds is
/// asked about once a week, not every day it holds.
@Suite("The weekly check-in")
struct WeeklyCheckInTests {
    /// A Monday; the cut starts three weeks on, also a Monday.
    let start = Day(year: 2026, month: 3, day: 2)
    var cutStart: Day { start.adding(days: 21) }

    var cut: PhasePlan {
        PhasePlan(
            phases: [PlannedPhase(kind: .cut, weeks: 12, start: cutStart)], headline: "", reasons: [], confidence: nil, arc: "",
            created: cutStart.date())
    }

    func checkIn(on day: Day, planCheck: String? = nil) -> CheckIn {
        CheckIn(
            id: CheckIn.id(for: day), day: day, expenditure: 2_600, kcal: 2_150, protein: 170, carbs: 220, fat: 70, status: .updated,
            reason: "Maintenance holding at about 2,600 kcal.", planCheck: planCheck, updatedAt: day.date())
    }

    /// Full days at 2,600 kcal through yesterday, weighed each morning at 84 kg, the cut in force,
    /// and Stadig Lift saying strength is `strength`.
    func state(today: Day, strength: Trajectory, checkIns: [CheckIn], plan: PhasePlan? = nil) -> MacroState {
        var entries: [FoodEntry] = []
        var statuses: [DayStatus] = []
        for day in DayRange(start, today.adding(days: -1)).days {
            for meal in [8.0, 12, 15, 19] {
                let date = day.date().addingTimeInterval(meal * 3600)
                entries.append(
                    FoodEntry(
                        date: date, name: "Meal", amountLabel: "1", nutrients: Nutrients(kcal: 650, protein: 35, carbs: 70, fat: 22),
                        source: .search, updatedAt: date))
            }
            statuses.append(DayStatus(day: day, state: .complete))
        }
        let weighIns = DayRange(start, today).days.map { WeighIn(date: $0.date().addingTimeInterval(7 * 3600), kg: 84) }
        let lift = AppSummary(app: .liftTrack, stats: [StatReading(stat: .strength, score: 55, label: "Strength", trend: strength)])
        return MacroState(
            profile: profile(goals: [.leaner]), settings: MacroSettings(assessmentStart: start), entries: entries, weighIns: weighIns,
            dayStatus: statuses, plan: plan ?? cut, lift: lift, checkIns: checkIns, today: today,
            now: today.date().addingTimeInterval(10 * 3600))
    }

    @Test("the next is the Monday nearest a week on, whichever day the last was")
    func nextIsAMonday() {
        for offset in 0..<7 {
            let day = start.adding(days: offset)
            let next = CheckIns.next(after: day)
            #expect(next.weekday == .monday, "after a \(day.weekday)")
            #expect((4...10).contains(day.days(until: next)), "after a \(day.weekday): \(day.days(until: next)) days")
        }
        #expect(CheckIns.next(after: start) == start.adding(days: 7))
        // Started on a Thursday, the first is four days on; on a Friday, ten.
        #expect(CheckIns.next(after: start.adding(days: 3)) == start.adding(days: 7))
        #expect(CheckIns.next(after: start.adding(days: 4)) == start.adding(days: 14))
        #expect(CheckIns.isDue(last: nil, today: start.adding(days: 2)))
    }

    /// Half a year of someone who starts a plan on a Thursday and opens the app on most days, not
    /// all: each check-in comes on a Monday, or on the first day the app's opened after a Monday
    /// missed, and the one after that is a Monday again.
    @Test("a simulated person checks in on Mondays, and a Monday missed is made up the next time they open the app")
    func simulatedPerson() {
        for seed in [1, 7, 42, 2026] as [UInt64] {
            var rng = SplitMix(seed: seed)
            let started = start.adding(days: 3)
            var checkIns = [started]
            var opened: Set<Day> = []
            for day in DayRange(started.adding(days: 1), started.adding(days: 26 * 7)).days where rng.uniform() < 0.75 {
                opened.insert(day)
                if let last = checkIns.last, CheckIns.isDue(last: checkIn(on: last), today: day) { checkIns.append(day) }
            }
            for (last, next) in zip(checkIns, checkIns.dropFirst()) {
                let due = CheckIns.next(after: last)
                #expect(due.weekday == .monday, "seed \(seed): after \(last)")
                if opened.contains(due) {
                    #expect(next == due && (4...10).contains(last.days(until: next)), "seed \(seed): \(last) then \(next)")
                } else {
                    // Made up on the first day the app's opened after the Monday it was due.
                    #expect(next > due && DayRange(due, next.adding(days: -1)).days.allSatisfy { !opened.contains($0) }, "seed \(seed): \(next)")
                }
            }
            let missed = DayRange(started, started.adding(days: 26 * 7)).days.filter { $0.weekday == .monday && !opened.contains($0) }
            let late = checkIns.dropFirst().filter { $0.weekday != .monday }
            #expect(late.count <= missed.count, "seed \(seed): \(late.count) late of \(missed.count) Mondays missed")
            #expect(checkIns.count >= 24, "seed \(seed): \(checkIns.count) check-ins in half a year")
        }
    }

    @Test("a rule that starts to hold midweek waits for the Monday's check-in")
    func midweekWaits() throws {
        let weekOne = [checkIn(on: cutStart), checkIn(on: cutStart.adding(days: 7))]
        let wednesday = cutStart.adding(days: 9)
        let midweek = MacroAnalyst.analyse(state(today: wednesday, strength: .regressing, checkIns: weekOne))
        #expect(PhasePlanner.check(cut, input: midweek.plannerInput) != nil, "the rule holds")
        #expect(midweek.dueCheckIn == nil && midweek.planCheck == nil)

        let monday = cutStart.adding(days: 14)
        let checked = MacroAnalyst.analyse(state(today: monday, strength: .regressing, checkIns: weekOne))
        let due = try #require(checked.dueCheckIn)
        #expect(due.day == monday && due.planCheck == "Strength is dropping during the cut, so it ends early with a diet break.")
        let change = try #require(checked.planCheck)
        #expect(change.phases.last?.kind == .dietBreak && change.phases.last?.start == monday)
        #expect(!checked.actions.contains { $0.title == "Plan check" }, "Today shows it with the check-in, not as an action")
        #expect(checked.weekCheckIn == .planCheck(change))

        // With strength holding up, Monday's check-in leaves the plan be, and Today shows the targets.
        let steady = MacroAnalyst.analyse(state(today: monday, strength: .onPace, checkIns: weekOne))
        let plain = try #require(steady.dueCheckIn)
        #expect(plain.planCheck == nil && steady.planCheck == nil)
        #expect(steady.weekCheckIn == .targets(plain, previous: weekOne[1]))
    }

    @Test("Today shows the week's check-in for two days unless it's put away, and never the person's own between two")
    func shownOnToday() {
        let monday = cutStart.adding(days: 14)
        let weeks = [checkIn(on: cutStart), checkIn(on: cutStart.adding(days: 7)), checkIn(on: monday)]
        #expect(CheckIns.shown(weeks, planCheck: nil, putAway: nil, today: monday.adding(days: 2)) == .targets(weeks[2], previous: weeks[1]))
        #expect(CheckIns.shown(weeks, planCheck: nil, putAway: nil, today: monday.adding(days: 3)) == nil, "three days on, it's on Plan")
        #expect(CheckIns.shown(weeks, planCheck: nil, putAway: monday, today: monday) == nil, "put away")
        #expect(CheckIns.shown(weeks, planCheck: nil, putAway: cutStart.adding(days: 7), today: monday) != nil, "last week's put away")
        // A plan started, or the person's own targets set, on Wednesday is their own doing.
        let started = weeks + [checkIn(on: monday.adding(days: 2))]
        #expect(CheckIns.shown(started, planCheck: nil, putAway: nil, today: monday.adding(days: 2)) == nil)
        // Nor are the first targets, with nothing before them.
        #expect(CheckIns.shown([checkIn(on: cutStart)], planCheck: nil, putAway: nil, today: cutStart) == nil)
        // A plan check comes first, put away or not, for as long as it's offered.
        let change = cut
        #expect(CheckIns.shown(weeks, planCheck: change, putAway: monday, today: monday.adding(days: 5)) == .planCheck(change))
    }

    @Test("found on Monday, it's offered through the week as the data has it that day, until it's kept")
    func offeredThroughTheWeek() throws {
        let monday = cutStart.adding(days: 14)
        let flagged = [checkIn(on: cutStart), checkIn(on: cutStart.adding(days: 7)), checkIn(on: monday, planCheck: "Strength is dropping.")]
        let wednesday = monday.adding(days: 2)
        let a = MacroAnalyst.analyse(state(today: wednesday, strength: .regressing, checkIns: flagged))
        let change = try #require(a.planCheck)
        // Used on Wednesday, the diet break starts Wednesday: Monday and Tuesday stay the cut's.
        #expect(change.phases.last?.kind == .dietBreak && change.phases.last?.start == wednesday)
        #expect(change.phases.first?.endedEarly == wednesday.adding(days: -1))

        // Gone once the data no longer says so, and once the person keeps their plan.
        #expect(MacroAnalyst.analyse(state(today: wednesday, strength: .onPace, checkIns: flagged)).planCheck == nil)
        var kept = flagged
        kept[2].planCheck = nil
        #expect(MacroAnalyst.analyse(state(today: wednesday, strength: .regressing, checkIns: kept)).planCheck == nil)
    }

    @Test("a finished plan isn't a plan check: it's a new recommendation, on Plan and Today every day until one's chosen")
    func finishedPlan() throws {
        let short = PhasePlan(
            phases: [PlannedPhase(kind: .cut, weeks: 2, start: cutStart)], headline: "", reasons: [], confidence: nil, arc: "",
            created: cutStart.date())
        let monday = cutStart.adding(days: 21)
        let a = MacroAnalyst.analyse(state(today: monday, strength: .regressing, checkIns: [checkIn(on: cutStart.adding(days: 7))], plan: short))
        #expect(!short.inForce(on: monday) && short.inForce(on: cutStart) && !short.inForce(on: cutStart.adding(days: -1)))
        #expect(PhasePlanner.check(short, input: a.plannerInput) == nil)
        #expect(PhasePlanner.review(short, input: a.plannerInput) != nil)
        #expect(a.dueCheckIn != nil && a.dueCheckIn?.planCheck == nil && a.planCheck == nil)
        #expect(a.actions.contains { $0.title == "Plan finished" })
    }

    @Test("a check-in from before the plan check reads as one that found nothing")
    func olderCheckInsDecode() throws {
        let json = """
            {"id":"3B9F6E2C-8A41-4D7E-B5C0-1E6A9D4F2C87","day":"2026-03-02","expenditure":2600,"kcal":2150,"protein":170,
            "carbs":220,"fat":70,"status":"updated","reason":"Maintenance holding.","updatedAt":0}
            """
        let old = try JSONDecoder().decode(CheckIn.self, from: Data(json.utf8))
        #expect(old.planCheck == nil && old.kcal == 2_150)
        let flagged = checkIn(on: start, planCheck: "Strength is dropping.")
        #expect(try JSONDecoder().decode(CheckIn.self, from: JSONEncoder().encode(flagged)).planCheck == "Strength is dropping.")
    }
}
