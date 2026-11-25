import Foundation
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// The week's check-in through the app model: the change to the plan it found, kept or used, and the
/// check-in put away on Today, each as a relaunch over the same store finds it. The rules are
/// NutritionEngine's (`WeeklyCheckInTests`).
@MainActor
struct WeekCheckInAppTests {
    /// The sample person ten days into a cut, with Stadig Lift saying strength is `strength` and
    /// the last check-in on the cut's first day: ten days back, a check-in is due today whatever
    /// day of the week it is.
    func cutting(_ environment: TestEnvironment, strength: Trajectory, lastCheckIn: Int = 10) throws -> AppModel {
        let model = environment.model()
        SampleData.seedIfEmpty(model)
        let lift = AppSummary(app: .liftTrack, stats: [StatReading(stat: .strength, score: 55, label: "Strength", trend: strength)])
        try environment.shared.write(lift, to: .summary(.liftTrack), by: .liftTrack)
        model.readShared()
        let begun = model.today.adding(days: -10)
        let cut = PhasePlan(phases: [PlannedPhase(kind: .cut, weeks: 8, start: begun)], headline: "Cut", reasons: [], confidence: nil, arc: "")
        model.start(cut)
        // As if the cut had been started back then: nothing's been seen of today's check-in.
        model.updateSettings { $0.checkInPutAway = nil }
        for old in model.store.all(CheckIn.self) { model.store.delete(CheckIn.self, id: old.id) }
        let maintenance = try #require(model.analysis?.maintenance.kcal)
        model.store.save(CheckIns.start(cut, today: model.today.adding(days: -lastCheckIn), maintenance: maintenance, weightKg: 84, referenceKg: 80))
        model.reload()
        return model
    }

    @Test func aChangeFoundAtTheCheckInIsOfferedUntilItsKept() throws {
        let environment = TestEnvironment()
        let model = try cutting(environment, strength: .regressing)
        let checkIn = try #require(model.checkIns.last)
        #expect(checkIn.day == model.today && checkIn.planCheck != nil, "the weekly check-in applied itself and looked at the plan")
        let change = try #require(model.analysis?.planCheck)
        #expect(model.analysis?.weekCheckIn == .planCheck(change), "Today shows it")
        #expect(!(model.analysis?.actions.contains { $0.title == "Plan check" } ?? true))

        model.keepPlan()
        #expect(model.analysis?.planCheck == nil && model.analysis?.weekCheckIn == nil && model.checkIns.last?.planCheck == nil)
        #expect(model.plan?.phases.map(\.kind) == [.cut])
        // Kept on every device, and not asked again until the next check-in.
        let again = environment.model()
        #expect(again.analysis?.planCheck == nil && again.checkIns.count == model.checkIns.count)
    }

    @Test func usingItStartsTheChangeToday() throws {
        let environment = TestEnvironment()
        let model = try cutting(environment, strength: .regressing)
        let change = try #require(model.analysis?.planCheck)
        model.start(change)
        let plan = try #require(model.plan)
        #expect(plan.phases.last?.kind == .dietBreak && plan.phases.last?.start == model.today)
        #expect(model.analysis?.planCheck == nil, "the plan's new check-in replaces the one that found it")
        #expect(model.analysis?.weekCheckIn == nil, "choosing the plan saw to the week's check-in")
        #expect(environment.model().analysis?.planCheck == nil)
    }

    @Test func aRuleThatHoldsBetweenCheckInsWaits() throws {
        // Checked in yesterday: the next is days away, so the cut stands until then.
        let model = try cutting(TestEnvironment(), strength: .regressing, lastCheckIn: 1)
        #expect(model.checkIns.last?.day == model.today.adding(days: -1))
        #expect(model.analysis?.planCheck == nil && model.analysis?.weekCheckIn == nil)
    }

    @Test func theCheckInIsPutAwayOnEveryDevice() throws {
        let environment = TestEnvironment()
        let model = try cutting(environment, strength: .onPace)
        let checkIn = try #require(model.checkIns.last)
        #expect(checkIn.day == model.today && checkIn.planCheck == nil)
        guard case .targets(let shown, _)? = model.analysis?.weekCheckIn else {
            Issue.record("Today shows the check-in: \(String(describing: model.analysis?.weekCheckIn))")
            return
        }
        #expect(shown == checkIn)

        model.putAwayCheckIn()
        #expect(model.settings.checkInPutAway == model.today && model.analysis?.weekCheckIn == nil)
        #expect(environment.model().analysis?.weekCheckIn == nil)
    }
}
