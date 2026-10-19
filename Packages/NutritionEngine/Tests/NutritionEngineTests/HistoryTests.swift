import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// The history table on iPad and the Mac: a row a day, judged the way the analysis judges it, and
/// the column sorts.
@Suite("Day history")
struct HistoryTests {
    let start = Day(year: 2026, month: 3, day: 2)
    var today: Day { start.adding(days: 35) }

    /// Five weeks of 2,600 kcal days marked complete, weighed each morning at 84 kg, with a cut from
    /// week four; then the exceptions the tests need.
    func state(
        partial: Day? = nil, unmarked: Day? = nil, fasted: Day? = nil, empty: Day? = nil, ignoredWeighIn: Day? = nil,
        vacation: DayRange? = nil
    ) -> MacroState {
        var entries: [FoodEntry] = []
        var weighIns: [WeighIn] = []
        var statuses: [DayStatus] = []
        for day in DayRange(start, today.adding(days: -1)).days where day != empty && day != fasted {
            let meals = day == partial ? [8.0] : [8.0, 12, 15, 19]
            for meal in meals {
                let date = day.date().addingTimeInterval(meal * 3600)
                entries.append(
                    FoodEntry(
                        date: date, name: "Meal", amountLabel: "1",
                        nutrients: Nutrients(kcal: 650, protein: 35, carbs: 70, fat: 22, fiber: 8), source: .search, updatedAt: date))
            }
            if day != partial && day != unmarked { statuses.append(DayStatus(day: day, state: .complete)) }
        }
        if let partial { statuses.append(DayStatus(day: partial, state: .partial)) }
        if let fasted { statuses.append(DayStatus(day: fasted, state: .fasting)) }
        for day in DayRange(start, today).days {
            weighIns.append(WeighIn(date: day.date().addingTimeInterval(7 * 3600), kg: 84))
            if day == ignoredWeighIn {
                weighIns.append(WeighIn(date: day.date().addingTimeInterval(9 * 3600), kg: 90, excluded: true))
            }
        }
        // Today's breakfast, so far.
        entries.append(
            FoodEntry(
                date: today.date().addingTimeInterval(8 * 3600), name: "Breakfast", amountLabel: "1",
                nutrients: Nutrients(kcal: 500, protein: 30, carbs: 50, fat: 15), source: .search))
        let cut = PhasePlan(
            phases: [PlannedPhase(kind: .cut, weeks: 12, start: start.adding(days: 21))], headline: "", reasons: [],
            confidence: nil, arc: "", created: start.adding(days: 21).date())
        let modes = vacation.map { [LifeModePeriod(kind: .vacation, start: $0.start, end: $0.end, createdBy: .macroTrack)] } ?? []
        return MacroState(
            profile: profile(), settings: MacroSettings(assessmentStart: start), entries: entries, weighIns: weighIns,
            dayStatus: statuses, plan: cut, lifeModes: modes, today: today, now: today.date().addingTimeInterval(10 * 3600))
    }

    func rows(_ state: MacroState) -> [HistoryDay] { DayHistory.rows(state, MacroAnalyst.analyse(state)) }

    func row(_ rows: [HistoryDay], _ day: Day) throws -> HistoryDay { try #require(rows.first { $0.day == day }) }

    @Test("a row a day from the start to today, newest first, with the day's food, weight and trend")
    func range() throws {
        let rows = rows(state())
        #expect(rows.count == 36)
        #expect(rows.first?.day == today && rows.last?.day == start)
        let yesterday = try row(rows, today.adding(days: -1))
        #expect(yesterday.intake?.kcal == 2600 && yesterday.intake?.fiber == 32 && yesterday.entries == 4)
        #expect(yesterday.weighIn == 84)
        #expect(abs((yesterday.trend ?? 0) - 84) < 0.01)
        let todayRow = try row(rows, today)
        #expect(todayRow.status == .inProgress && todayRow.kcal == 500)
    }

    @Test("statuses as the analysis reads days: complete, fasted, partial (marked or not enough), unknown")
    func statuses() throws {
        let partial = start.adding(days: 10)
        let unmarked = start.adding(days: 11)
        let fasted = start.adding(days: 12)
        let empty = start.adding(days: 13)
        let rows = rows(state(partial: partial, unmarked: unmarked, fasted: fasted, empty: empty))
        #expect(try row(rows, start.adding(days: 9)).status == .complete)
        #expect(try row(rows, partial).status == .partial)
        // Four live entries reaching the day's need teach the estimate without a mark.
        #expect(try row(rows, unmarked).status == .complete)
        #expect(try row(rows, fasted).status == .fasting)
        let nothing = try row(rows, empty)
        #expect(nothing.status == .unknown && nothing.intake == nil && nothing.hit == nil)
    }

    @Test("each day is judged by its own targets: protein only in the assessment, the cut's calories after")
    func targets() throws {
        let state = state()
        let analysis = MacroAnalyst.analyse(state)
        let rows = DayHistory.rows(state, analysis)
        let assessing = try row(rows, start.adding(days: 5))
        #expect(assessing.targets.kcal == nil && assessing.targets.protein != nil)
        #expect(assessing.kcalOverTarget == nil)
        let cutting = try row(rows, today.adding(days: -2))
        let kcal = try #require(cutting.targets.kcal)
        #expect(kcal < 2600)
        #expect(cutting.kcalOverTarget == 2600 - kcal)
        // The same targets the analysis scores those days by.
        #expect(analysis.dayTargets.count >= 20)
        for (day, scored) in analysis.dayTargets {
            #expect(MacroAnalyst.targets(on: day, state, analysis) == scored, "\(day)")
        }
        #expect(try row(rows, today).targets == analysis.targets)
    }

    @Test("a hit is a complete day within its targets; other days aren't judged")
    func hits() throws {
        let partial = today.adding(days: -3)
        let rows = rows(state(partial: partial))
        // 2,600 kcal against a cut's target is more than 10% over.
        #expect(try row(rows, today.adding(days: -2)).hit == false)
        // In the assessment only protein counts: 140 g against about 1.6 g/kg of 84 kg.
        #expect(try row(rows, start.adding(days: 5)).hit == true)
        #expect(try row(rows, partial).hit == nil)
        #expect(try row(rows, today).hit == nil)
    }

    @Test("the counted weigh-in: an ignored reading isn't the day's weight")
    func weighIns() throws {
        let day = start.adding(days: 20)
        #expect(try row(rows(state(ignoredWeighIn: day)), day).weighIn == 84)
    }

    @Test("a vacation's days keep its targets")
    func vacation() throws {
        let away = DayRange(start.adding(days: 24), start.adding(days: 27))
        let rows = rows(state(vacation: away))
        #expect(try row(rows, start.adding(days: 25)).targets.mode == .vacation)
    }

    @Test("sorting by a column puts days without the value last either way, ties newest first")
    func sorting() throws {
        let empty = start.adding(days: 13)
        let rows = rows(state(empty: empty))
        let byKcal = rows.sorted(using: HistoryOrder(.kcal, order: .reverse))
        #expect(byKcal.first?.kcal == 2600 && byKcal.first?.day == today.adding(days: -1))
        #expect(byKcal.last?.day == empty)
        let up = rows.sorted(using: HistoryOrder(.kcal, order: .forward))
        #expect(up.first?.day == today, "today's 500 kcal is the least")
        #expect(up.last?.day == empty, "nothing logged goes last ascending too")
        let byDay = rows.sorted(using: HistoryOrder(.day, order: .forward))
        #expect(byDay.first?.day == start)
        let byStatus = rows.sorted(using: HistoryOrder(.status))
        #expect(byStatus.first?.status == .complete && byStatus.last?.status == .inProgress)
    }

    @Test("nothing logged or weighed yet: no history")
    func emptyHistory() {
        let state = MacroState(profile: profile(), settings: MacroSettings(), today: today)
        #expect(DayHistory.rows(state, MacroAnalyst.analyse(state)).isEmpty)
    }
}
