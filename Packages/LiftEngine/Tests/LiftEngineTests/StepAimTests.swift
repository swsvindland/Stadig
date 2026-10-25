import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

@Suite("Step aim")
struct StepAimTests {
    /// A Friday.
    let today = Day(year: 2026, month: 10, day: 16)

    /// Cutting for two weeks: 8,000 a day before, 6,000 since, 2,500 so far today.
    func cutting(
        steps extra: [StepDay] = [], activities: [ActivityLog] = [], recurring: [RecurringActivity] = [],
        lifeModes: [LifeModePeriod] = []
    ) -> LiftState {
        let since = today.adding(days: -14)
        var settings = LiftSettings(selfReportedPhase: .cutting, assessmentStart: today.adding(days: -60))
        settings.selfReportedPhaseSince = since
        var steps =
            DayRange(since.adding(days: -28), since.adding(days: -1)).days.map { StepDay(day: $0, steps: 8_000) }
            + DayRange(since, today.adding(days: -1)).days.map { StepDay(day: $0, steps: 6_000) }
            + [StepDay(day: today, steps: 2_500)]
        for day in extra {
            steps.removeAll { $0.day == day.day }
            steps.append(day)
        }
        return LiftState(
            profile: Fixture.profile(recurring: recurring), settings: settings, gym: Gym.preset(.fullGym, unit: .kg),
            catalog: Fixture.catalog, activities: activities, lifeModes: lifeModes, steps: steps, today: today)
    }

    @Test func aCutSetsTheAimFromTheUsualCountBeforeIt() {
        let a = Analyst.analyse(cutting())
        let steps = try! #require(a.steps)
        #expect(steps.baseline == 8_000 && steps.target == 10_000)
        // Last week averaged 6,000: back to the usual 8,000 first.
        #expect(steps.aim == 8_000 && steps.recent == 6_000 && steps.onTrack == false && steps.actionable)
        // Without Health steps there's nothing to show.
        var none = cutting()
        none.steps = []
        #expect(Analyst.analyse(none).steps == nil)
    }

    @Test func aRestDayBehindTheAimGetsAWalk() {
        let a = Analyst.analyse(cutting())
        let walk = try! #require(a.quests.first { $0.id.hasSuffix("-walk") })
        #expect(walk.title == "20-minute walk" && walk.minutes == 20 && walk.stat == .vitality && walk.timeOfDay == .evening)
        // Not on a class day, not once today reaches the aim, not while ill, not with a bad knee.
        let classDay = cutting(recurring: [RecurringActivity(activity: .bjj, weekdays: [today.weekday], minutes: 60, intensity: 7)])
        #expect(!Analyst.analyse(classDay).quests.contains { $0.id.hasSuffix("-walk") })
        let walked = cutting(steps: [StepDay(day: today, steps: 8_400)])
        #expect(!Analyst.analyse(walked).quests.contains { $0.id.hasSuffix("-walk") })
        let ill = cutting(lifeModes: [LifeModePeriod(kind: .illness(.systemic), start: today.adding(days: -1), createdBy: .liftTrack)])
        #expect(!Analyst.analyse(ill).quests.contains { $0.id.hasSuffix("-walk") })
        let knee = cutting(lifeModes: [
            LifeModePeriod(
                kind: .injury(Injury(parts: [InjuredPart(.knee, side: .left)], severity: .moderate)),
                start: today.adding(days: -3), createdBy: .liftTrack)
        ])
        #expect(!Analyst.analyse(knee).quests.contains { $0.id.hasSuffix("-walk") })
    }

    @Test func aLongUnloggedDayOnFootSpendsTheBudget() {
        let hike = today.adding(days: -2)
        let plain = Analyst.analyse(cutting()).fatigue.acute
        let hiked = Analyst.analyse(cutting(steps: [StepDay(day: hike, steps: 26_000)])).fatigue.acute
        #expect(hiked > plain)
        // Logged as a hike, it's counted once, as the hike.
        let log = ActivityLog(type: .hiking, start: hike.date().addingTimeInterval(9 * 3600), minutes: 240, intensity: 5)
        let logged = cutting(steps: [StepDay(day: hike, steps: 26_000)], activities: [log])
        let alone = cutting(activities: [log])
        #expect(Analyst.analyse(logged).fatigue.acute == Analyst.analyse(alone).fatigue.acute)
    }

    @Test func publishesCompleteDaysAndTheAim() {
        let state = cutting()
        let summary = Analyst.summary(state, Analyst.analyse(state))
        let steps = try! #require(summary.steps)
        #expect(steps.aim == 8_000 && steps.baseline == 8_000)
        #expect(steps.days.last?.day == today.adding(days: -1) && steps.days.count == 42)
    }

    @Test func thePhaseAnswerDatesTheUsualCount() {
        var state = cutting()
        #expect(state.phaseStart == today.adding(days: -14))
        #expect(state.stepsNeededSince == today.adding(days: -56))
        state.settings.selfReportedPhaseSince = nil
        #expect(state.phaseStart == today.adding(days: -60))
        #expect(state.stepsNeededSince == today.adding(days: -88))
        // Stadig Macro's phase start wins.
        state.nutrition = NutritionSummary(
            phase: NutritionPhase(kind: .cut, start: today.adding(days: -7), source: .macroTrack),
            maintenanceKcal: 2600, days: [])
        #expect(state.phaseStart == today.adding(days: -7))
    }
}
