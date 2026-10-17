import Foundation
import Testing
@testable import SystemCore

@Suite("Steps")
struct StepTests {
    /// A Friday.
    let today = Day(year: 2026, month: 10, day: 16)

    /// The same count every day in a range.
    func days(_ from: Day, _ to: Day, _ steps: Int) -> [StepDay] {
        DayRange(from, to).days.map { StepDay(day: $0, steps: steps) }
    }

    @Test func usualCountComesFromTheWeeksBeforeThePhase() {
        let anchor = Day(year: 2026, month: 10, day: 1)
        var history = days(Day(year: 2026, month: 9, day: 1), anchor.adding(days: -1), 7_000) + days(anchor, today, 9_000)
        // The phone on a desk, and a week in bed: neither is a habit.
        history[5].steps = 300
        history[6].steps = 450
        let ill = Set(DayRange(Day(year: 2026, month: 9, day: 20), Day(year: 2026, month: 9, day: 24)).days)
        for i in history.indices where ill.contains(history[i].day) { history[i].steps = 1_800 }
        #expect(Steps.baseline(history, anchor: anchor, today: today, exempt: ill) == 7_000)
        // Health that starts with the phase: its first four weeks stand in.
        #expect(Steps.baseline(days(anchor, today, 9_000), anchor: anchor, today: today) == 9_000)
        // Too few carried days anywhere: no usual count, so no aim.
        #expect(Steps.baseline(days(today.adding(days: -4), today, 9_000), anchor: anchor, today: today) == nil)
    }

    @Test func aCutAddsAboutTwoThousandAWeekAtATime() {
        #expect(Steps.target(baseline: 7_000, energy: .deficit, age: 35) == 9_000)
        // Last week's average plus a step, rounded up to the next 500, never past the target.
        #expect(Steps.weeklyAim(target: 9_000, baseline: 7_000, lastWeek: nil) == 8_000)
        #expect(Steps.weeklyAim(target: 9_000, baseline: 7_000, lastWeek: 7_400) == 8_500)
        #expect(Steps.weeklyAim(target: 9_000, baseline: 7_000, lastWeek: 8_600) == 9_000)
        // A bad week doesn't lower the aim under the usual count, and doesn't raise it either.
        #expect(Steps.weeklyAim(target: 9_000, baseline: 7_000, lastWeek: 4_000) == 7_000)
        // Already walking plenty: held, not pushed.
        #expect(Steps.target(baseline: 13_800, energy: .deficit, age: 35) == 14_000)
        #expect(Steps.weeklyAim(target: 14_000, baseline: 13_800, lastWeek: 13_000) == 14_000)
        // A low usual count goes to the floor, which is lower from 60.
        #expect(Steps.target(baseline: 5_000, energy: .deficit, age: 35) == 8_000)
        #expect(Steps.target(baseline: 4_000, energy: .deficit, age: 66) == 7_000)
    }

    @Test func outsideACutTheUsualCountIsHeld() {
        #expect(Steps.target(baseline: 9_200, energy: .maintenance, age: 35) == 9_000)
        #expect(Steps.target(baseline: 14_000, energy: .surplus, age: 35) == 10_000)
        #expect(Steps.target(baseline: 5_000, energy: .surplus, age: 35) == 8_000)
    }

    @Test func shownOnlyWhenThereIsSomethingToDo() {
        let anchor = today.adding(days: -30)
        let before = days(anchor.adding(days: -28), anchor.adding(days: -1), 9_200)
        // Maintaining at the usual count: nothing to say.
        let steady = Steps.aim(days: before + days(anchor, today, 9_300), anchor: anchor, energy: .maintenance, age: 35, today: today)
        #expect(steady?.aim == 9_000 && steady?.shown == false && steady?.onTrack == true)
        // Slipped by more than 1,000 a day: shown, and it says so.
        let slipped = Steps.aim(days: before + days(anchor, today.adding(days: -8), 9_000) + days(today.adding(days: -7), today, 7_000),
                                anchor: anchor, energy: .maintenance, age: 35, today: today)
        #expect(slipped?.shown == true && slipped?.onTrack == false && slipped?.gap == 2_000)
        #expect(slipped?.reason.contains("slipped") == true)
        // Below the floor: shown while it builds.
        let low = Steps.aim(days: days(anchor.adding(days: -28), today, 5_000), anchor: anchor, energy: .maintenance, age: 35, today: today)
        #expect(low?.shown == true && low?.target == 8_000 && low?.aim == 6_000)
        // A cut: always shown, even on track.
        let cut = Steps.aim(days: before + days(anchor, today, 11_500), anchor: anchor, energy: .deficit, age: 35, today: today)
        #expect(cut?.shown == true && cut?.target == 11_000 && cut?.onTrack == true)
        // The week shown is the last seven complete days, today kept apart.
        #expect(cut?.week.map(\.day) == DayRange(today.adding(days: -7), today.adding(days: -1)).days && cut?.today == 11_500)
    }

    @Test func longDaysOnFootCountOnlyWhenNobodyLoggedThem() {
        let hike = Day(year: 2026, month: 10, day: 10)
        let history = [StepDay(day: hike, steps: 22_000), StepDay(day: hike.adding(days: 1), steps: 14_000)]
        let long = Steps.longDays(history, baseline: 8_000)
        #expect(long.count == 1 && long.first?.day == hike && long.first?.minutes == 140)
        #expect(Steps.longDays(history, baseline: 8_000, skipping: [hike]).isEmpty)
    }

    @Test func aFallInStepsIsMeasuredAgainstTheMonthBefore() {
        let window = DayRange(today.adding(days: -21), today.adding(days: -1))
        let before = days(window.start.adding(days: -28), window.start.adding(days: -1), 11_000)
        let fell = Steps.fall(before + days(window.start, window.end, 6_000), window: window)
        #expect(fell?.before == 11_000 && fell?.during == 6_000)
        #expect(Steps.fall(before + days(window.start, window.end, 10_000), window: window) == nil)
        #expect(abs(Steps.kcalPerStep(kg: 80) - 0.04) < 1e-9)
    }
}
