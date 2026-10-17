import Foundation
import Testing
import SystemCore
@testable import NutritionEngine

@Suite("Steps in check-ins")
struct StepCheckInTests {
    /// A cut where real maintenance has dropped to 2,350 while last week's check-in still says
    /// 2,600: eating 2,100, logging every day, weighing in daily. Checked in on day 35.
    struct Cut {
        let eater = SimulatedEater(maintenance: 2_350, startKg: 90, logging: 1, noiseKg: 0.2)
        let run: SimulatedEater.Run
        let day: Day
        let previous: CheckIn
        let phase: PlannedPhase

        init() {
            run = eater.run(days: 35) { _, _ in 2_100 }
            day = eater.start.adding(days: 35)
            previous = CheckIn(day: day.adding(days: -7), expenditure: 2_600, kcal: 2_100, protein: 180, carbs: 190, fat: 65,
                               status: .updated, reason: "Last week")
            phase = PlannedPhase(kind: .cut, weeks: 12, start: eater.start)
        }

        /// Steps a day in the four weeks before the check-in's window, then during it.
        func steps(before: Int, during: Int) -> StepSummary {
            let window = DayRange(day.adding(days: -21), day.adding(days: -1))
            let days = DayRange(window.start.adding(days: -28), window.start.adding(days: -1)).days.map { StepDay(day: $0, steps: before) }
                + window.days.map { StepDay(day: $0, steps: during) }
            return StepSummary(days: days, aim: 10_000, baseline: before)
        }

        func review(previous: CheckIn? = nil, steps: StepSummary?) -> CheckIn {
            let trend = Weight.trend(run.weighIns.filter { $0.day < day }, through: day.adding(days: -1))
            return CheckIns.review(previous: previous ?? self.previous, trend: trend, usable: usable(run).filter { $0.key < day }, today: day,
                                   phase: phase, weightKg: trend.latest?.trend ?? 90, referenceKg: 90, fallbackExpenditure: 2_600,
                                   steps: steps)
        }
    }

    @Test func fewerStepsHoldTheTargetsOnceAndSaySo() {
        let cut = Cut()
        // Without steps, a lower maintenance moves the targets down.
        let plain = cut.review(steps: nil)
        #expect(plain.status == .updated && plain.expenditure < 2_600 && plain.kcal < cut.previous.kcal, "\(plain)")
        // Steps fell from 11,000 to 6,000 (about 220 kcal at 88 kg): maintenance holds, and the reason says to walk.
        let held = cut.review(steps: cut.steps(before: 11_000, during: 6_000))
        #expect(held.status == .steps && held.expenditure == 2_600 && abs(held.kcal - cut.previous.kcal) <= 25, "\(held)")
        #expect(held.reason.contains("Steps fell") && held.reason.contains("10,000"), "\(held.reason)")
        // Still down a week later: the targets follow the data, and still name the steps.
        let next = cut.review(previous: held, steps: cut.steps(before: 11_000, during: 6_000))
        #expect(next.status == .updated && next.expenditure < 2_600 && next.reason.contains("Steps fell"), "\(next)")
        // Steps that held steady change nothing.
        let steady = cut.review(steps: cut.steps(before: 9_000, during: 8_800))
        #expect(steady.status == plain.status && steady.kcal == plain.kcal && steady.reason == plain.reason)
    }

    @Test func stepsMoveTheFormulaNotTheWalksTwice() {
        let assumed = Energy.activityFactor(trainingDays: 4, otherActiveMinutes: 0)
        #expect(abs(assumed - (1.35 + 0.16)) < 1e-9)
        #expect(Energy.activityFactor(trainingDays: 4, otherActiveMinutes: 0, dailySteps: 4_000) < assumed)
        #expect(Energy.activityFactor(trainingDays: 4, otherActiveMinutes: 0, dailySteps: 12_000) > assumed)
        #expect(abs(Energy.activityFactor(trainingDays: 4, otherActiveMinutes: 0, dailySteps: 7_500) - assumed) < 1e-9)
    }
}
