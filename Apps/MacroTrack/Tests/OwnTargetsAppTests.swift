import Foundation
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// The person's own targets through the app model: what's saved when they're set, kept and left, and
/// what Today, the widgets, the Watch's badge and Stadig Lift then see. The rules are NutritionEngine's
/// (`OwnTargetsTests`).
@MainActor
struct OwnTargetsAppTests {
    /// A coach's 180 g protein, 210 g carbs and 60 g fat: 2,100 kcal.
    let coach = MacroTargets.grams(protein: 180, carbs: 210, fat: 60)

    /// The sample person with the recommended plan started today.
    func planned(_ environment: TestEnvironment = TestEnvironment()) throws -> AppModel {
        let model = environment.model()
        SampleData.seedIfEmpty(model)
        model.start(try #require(model.recommendation))
        return model
    }

    @Test func settingThemReplacesTodaysCheckInAndEverythingShowsThem() throws {
        let environment = TestEnvironment()
        let model = try planned(environment)
        let plans = try #require(model.analysis?.planNumbers)
        #expect(model.analysis?.planSource == .plan && model.analysis?.targets.kcal == plans.kcal)

        model.setOwnTargets(coach)
        #expect(model.checkIns.count == 1, "one check-in a day: the plan's first is replaced")
        let saved = try #require(model.checkIns.last)
        #expect(saved.isOwn && saved.id == CheckIn.id(for: model.today) && saved.own == coach)
        #expect(saved.plan == plans, "the plan's numbers carried under them")
        let analysis = try #require(model.analysis)
        #expect(analysis.targets.mode == .own && analysis.targets.kcal == 2_100 && analysis.targets.protein == 180)
        #expect(analysis.own?.since == model.today)
        #expect(analysis.planNumbers == plans, "Plan still says what the plan would set")
        #expect(TodayLogger.eyebrow(model).hasSuffix("· Your targets"))
        // The widgets and the Watch say whose targets these are; Stadig Lift keeps the plan's phase.
        let snapshot = MacroSnapshot.load(from: environment.widgetURL)
        #expect(snapshot.kcalTarget == 2_100 && snapshot.proteinTarget == 180 && snapshot.badge == "Your targets")
        #expect(environment.shared.read(.nutrition)?.phase?.kind == model.plan?.phases.first?.kind)
        // A relaunch over the same store reads them back.
        let again = environment.model()
        #expect(again.analysis?.targets.mode == .own && again.analysis?.targets.kcal == 2_100)
    }

    @Test func goingBackPutsThePlansNumbersInForceAsShown() throws {
        let model = try planned()
        model.setOwnTargets(coach)
        let shown = try #require(model.analysis?.planNumbers)
        model.useThePlansTargets()
        let back = try #require(model.checkIns.last)
        #expect(!back.isOwn && back.own == shown && model.checkIns.count == 1)
        #expect(model.analysis?.targets.mode == .phase && model.analysis?.targets.kcal == shown.kcal)
        #expect(model.analysis?.own == nil)
        // Nothing to go back from now.
        model.useThePlansTargets()
        #expect(model.checkIns.last == back)
    }

    @Test func startingAPlanTakesOverFromThem() throws {
        let model = try planned()
        model.setOwnTargets(coach)
        let other = PhasePlan(
            phases: [PlannedPhase(kind: .maintenance, weeks: 8, start: model.today)], headline: "Mine", reasons: [], confidence: nil, arc: "")
        model.start(other)
        #expect(model.analysis?.own == nil && model.analysis?.targets.mode == .phase)
        #expect(model.checkIns.count == 1 && model.checkIns.last?.isOwn == false)
    }

    @Test func theWeeksCheckInKeepsThem() throws {
        let model = try planned()
        // Set a week ago: today's check-in is due.
        let analysis = try #require(model.analysis)
        for old in model.store.all(CheckIn.self) { model.store.delete(CheckIn.self, id: old.id) }
        model.store.save(OwnTargets.record(coach, analysis, today: model.today.adding(days: -7)))
        model.reload()
        let kept = try #require(model.checkIns.last)
        #expect(model.checkIns.count == 2 && kept.day == model.today, "the weekly check-in applied itself")
        #expect(kept.isOwn && kept.own == coach && kept.plan != nil, "\(kept)")
        #expect(kept.reason.hasPrefix("Your own targets hold."))
        #expect(model.analysis?.targets.kcal == 2_100)
        #expect(model.analysis?.own?.since == model.today.adding(days: -7))
    }

    @Test func setAtOnboardingTheAssessmentRunsUnderThem() throws {
        let model = TestEnvironment().model()
        model.completeOnboarding(profile: .sample(), history: .none, weightKg: 82, own: (coach, 2_600))
        #expect(model.onboarded && model.settings.assessmentStart == model.today)
        #expect(model.weighIns.map(\.kg) == [82])
        let saved = try #require(model.checkIns.last)
        #expect(model.checkIns.count == 1 && saved.isOwn && saved.expenditure == 2_600 && saved.plan == nil)
        let analysis = try #require(model.analysis)
        #expect(analysis.targets.mode == .own && analysis.targets.kcal == 2_100)
        #expect(analysis.assessment?.complete == false, "the assessment still runs")
        #expect(analysis.planSource == .maintenance)
        #expect(model.plan == nil && model.recommendation != nil)

        // Back before a plan: the assessment again, asking only for protein.
        model.useThePlansTargets()
        #expect(model.checkIns.isEmpty)
        #expect(model.analysis?.targets.mode == .assessment && model.analysis?.targets.kcal == nil)
    }

    @Test func setInTheAssessmentTheyreTheDays() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.setOwnTargets(coach)
        #expect(model.analysis?.targets.mode == .own)
        #expect(model.checkIns.last?.plan == nil, "no plan yet, so no numbers of its to carry")
    }
}
