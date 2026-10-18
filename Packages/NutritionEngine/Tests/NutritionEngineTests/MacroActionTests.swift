import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// The "do this next" list on Today, each kind from a fixed day and a fixed time of day.
@Suite("Today's actions")
struct MacroActionTests {
    let start = Day(year: 2026, month: 3, day: 2)
    var today: Day { start.adding(days: 35) }

    /// Full days at 2,600 kcal and 140 g protein through `last`, weighed each morning at 84 kg,
    /// with a cut from week four; today has `todayProtein` grams logged so far, if anything.
    func state(
        through last: Day? = nil, weighedToday: Bool = true, todayProtein: Double? = nil, hour: Double = 10,
        plan: PhasePlan?? = nil, calendar: SystemCalendar? = nil
    ) -> MacroState {
        var entries: [FoodEntry] = []
        var weighIns: [WeighIn] = []
        var statuses: [DayStatus] = []
        for day in DayRange(start, last ?? today.adding(days: -1)).days {
            for meal in [8.0, 12, 15, 19] {
                let date = day.date().addingTimeInterval(meal * 3600)
                entries.append(
                    FoodEntry(
                        date: date, name: "Meal", amountLabel: "1", nutrients: Nutrients(kcal: 650, protein: 35, carbs: 70, fat: 22),
                        source: .search, updatedAt: date))
            }
            statuses.append(DayStatus(day: day, state: .complete))
        }
        for day in DayRange(start, today.adding(days: weighedToday ? 0 : -1)).days {
            weighIns.append(WeighIn(date: day.date().addingTimeInterval(7 * 3600), kg: 84))
        }
        if let todayProtein {
            entries.append(
                FoodEntry(
                    date: today.date().addingTimeInterval(8 * 3600), name: "Breakfast", amountLabel: "1",
                    nutrients: Nutrients(kcal: 600, protein: todayProtein, carbs: 60, fat: 15), source: .search))
        }
        let cut = PhasePlan(
            phases: [PlannedPhase(kind: .cut, weeks: 12, start: start.adding(days: 21))], headline: "", reasons: [],
            confidence: nil, arc: "", created: start.adding(days: 21).date())
        return MacroState(
            profile: profile(), settings: MacroSettings(assessmentStart: start), entries: entries, weighIns: weighIns,
            dayStatus: statuses, plan: plan ?? cut, calendar: calendar, today: today,
            now: today.date().addingTimeInterval(hour * 3600))
    }

    func actions(_ state: MacroState) -> [MacroAction] { MacroAnalyst.analyse(state).actions }
    func kinds(_ state: MacroState) -> [MacroAction.Kind] { actions(state).map(\.kind) }

    @Test("protein to go shows from mid-afternoon, by the analysis's own clock")
    func protein() throws {
        #expect(!kinds(state(todayProtein: 10, hour: 10)).contains(.protein))
        let late = try #require(actions(state(todayProtein: 10, hour: 16)).first { $0.kind == .protein })
        #expect(late.action.contains("protein-heavy dinner") && late.detail.contains("in a cut"), "\(late)")
        // A smaller gap is a shake.
        let close = try #require(actions(state(todayProtein: 140, hour: 16)).first { $0.kind == .protein })
        #expect(close.action == "A shake or Greek yogurt closes it.", "\(close.title)")
        // Nothing logged yet today: nothing to say about it.
        #expect(!kinds(state(hour: 16)).contains(.protein))
    }

    @Test("weigh in, until today's weigh-in is in")
    func weighIn() {
        #expect(kinds(state(weighedToday: false)).contains(.weighIn))
        #expect(!kinds(state(weighedToday: true)).contains(.weighIn))
    }

    @Test("an empty yesterday is worth filling in")
    func yesterday() {
        #expect(kinds(state(through: today.adding(days: -2))).contains(.logYesterday))
        #expect(!kinds(state()).contains(.logYesterday))
    }

    @Test("the plan is ready when the assessment is done")
    func planReady() {
        #expect(kinds(state(plan: .some(nil))).contains(.planReady))
        #expect(!kinds(state()).contains(.planReady))
    }

    @Test("a stalled scale during a deload diet break is expected")
    func whoosh() {
        let deload = SystemCalendar(
            currentBlock: DayRange(today.adding(days: -27), today.adding(days: 6)), deloads: [DayRange(today, today.adding(days: 6))],
            checkIns: [], publishedBy: .liftTrack)
        let a = MacroAnalyst.analyse(state(calendar: deload))
        #expect(a.targets.mode == .dietBreak && a.actions.contains { $0.kind == .whoosh })
        #expect(!kinds(state()).contains(.whoosh))
    }

    @Test("a finished plan says so without Lift Track's calendar")
    func planEnded() throws {
        let short = PhasePlan(
            phases: [PlannedPhase(kind: .cut, weeks: 4, start: start.adding(days: 7))], headline: "", reasons: [],
            confidence: nil, arc: "", created: start.adding(days: 7).date())
        let ended = try #require(actions(state(plan: short)).first { $0.kind == .reviewPlan })
        #expect(ended.id == "plan-ended-\(short.phases[0].end.iso)" && ended.title == "Plan finished")
        // Mid-plan, with no block ending today, there's nothing to review.
        #expect(!kinds(state()).contains(.reviewPlan))
    }

    @Test("the most important comes first")
    func order() {
        let list = actions(state(through: today.adding(days: -2), weighedToday: false, todayProtein: 10, hour: 16))
        #expect(Set(list.map(\.kind)).isSuperset(of: [.weighIn, .protein, .logYesterday]))
        #expect(list.map(\.priority) == list.map(\.priority).sorted(by: >))
        #expect(list.first?.kind == .protein)
    }
}
