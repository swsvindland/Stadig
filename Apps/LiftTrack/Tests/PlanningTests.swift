import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import SystemStore
import Testing

@testable import LiftTrack

/// Blocks, today's session and outside training: the wiring between the model and the engine.
@MainActor
@Suite("Planning")
struct PlanningTests {
    @Test("Today's session is planned from the block the analysis shows")
    func planFollowsTheAnalysis() throws {
        let model = TestApp().onboarded()
        let analysis = try #require(model.analysis)
        let plan = try #require(model.plan())
        let next = try #require(analysis.next)
        #expect(plan.mesocycleID == analysis.mesocycle?.id)
        #expect(plan.dayID == next.day.id)
        #expect(plan.assessment)
        #expect(plan.deload == (analysis.block?.week(of: model.today) == .deload))
    }

    @Test("Short on time refits today's session to the minutes chosen")
    func refitToMinutes() throws {
        let model = TestApp().onboarded()
        let full = try #require(model.plan())
        let short = try #require(model.plan(minutes: 30))
        #expect(short.estimatedMinutes < full.estimatedMinutes)
        #expect(short.title == full.title)
    }

    @Test("A next block planned while the current one runs starts after it, so its deload and check-in stay")
    func nextBlockWaitsForTheCurrentOne() throws {
        let app = TestApp()
        let model = app.onboarded()
        // A real block three weeks in, the assessment long done.
        var current = model.generate(kind: .standard, start: Day.today.adding(days: -21))
        current.block.loadingWeeks = 4
        for assessment in model.mesocycles { app.store.delete(Mesocycle.self, id: assessment.id) }
        model.save(current)
        let block = try #require(model.analysis?.block)
        #expect(model.analysis?.mesocycle?.id == current.id)
        #expect(model.nextBlockStart == block.end.adding(days: 1))

        let next = model.generate(kind: .standard, start: model.nextBlockStart)
        model.accept(nextBlock: next)
        #expect(model.analysis?.mesocycle?.id == current.id)
        #expect(model.analysis?.upcoming?.id == next.id)
        #expect(model.mesocycles.first { $0.id == current.id }?.block.end == block.end)
    }

    @Test("An assessment finished early gives way today and ends yesterday")
    func assessmentFinishedEarly() throws {
        let model = TestApp().onboarded()
        var assessment = try #require(model.mesocycles.first)
        assessment.block.start = Day.today.adding(days: -14)
        model.save(assessment)
        #expect(model.nextBlockStart == model.today)

        let next = model.generate(kind: .standard, start: model.nextBlockStart)
        model.accept(nextBlock: next)
        #expect(model.mesocycles.first { $0.id == assessment.id }?.block.end == Day.today.adding(days: -1))
        #expect(model.analysis?.mesocycle?.id == next.id)
        #expect(model.analysis?.upcoming == nil)
        #expect(model.plan()?.mesocycleID == next.id)
    }

    @Test("A new block is built on the block running now, not one already planned to follow it")
    func generateUsesTheCurrentBlock() throws {
        let model = TestApp().onboarded()
        let first = try #require(model.mesocycles.first)
        let ahead = model.generate(kind: .standard, start: Day.today.adding(days: 60))
        model.save(ahead)
        #expect(model.analysis?.mesocycle?.id == first.id)
        #expect(model.analysis?.upcoming?.id == ahead.id)
        // The latest-starting block is the one planned ahead: the generator is handed the current one.
        #expect(model.mesocycles.last?.id == ahead.id)
        let profile = try #require(model.profile)
        let input = model.generatorInput(
            profile: profile, gym: model.gym, kind: .standard, start: model.nextBlockStart, loadingWeeks: 4, phase: .assumedMaintenance)
        #expect(input.previous?.id == first.id)
        // Which exercises carry over is the engine's to test; this only checks it plans at all from here.
        let again = model.generate(kind: .standard, start: model.nextBlockStart)
        #expect(!again.days.isEmpty)
    }

    @Test("Deload now does nothing until the Fatigue Budget offers one")
    func deloadNowNeedsASuggestion() throws {
        let model = TestApp().onboarded()
        #expect(model.analysis?.suggestedDeload == nil)
        let before = try #require(model.currentMesocycle)
        model.deloadNow(reason: "Tired")
        #expect(model.currentMesocycle?.block == before.block)
    }

    // MARK: Outside training

    private func workout(id: UUID = UUID(), hoursAgo: Double) -> ActivityLog {
        ActivityLog(
            id: id, type: .running, start: Date().addingTimeInterval(-hoursAgo * 3600), minutes: 40,
            source: .health(id, sourceName: "Strava"))
    }

    @Test("Workouts from Health are imported once")
    func healthImportsOnce() {
        let model = TestApp().onboarded()
        let run = workout(hoursAgo: 20)
        #expect(model.importOutside([run]) == 1)
        model.reload()
        #expect(model.activities.map(\.id) == [run.id])
        #expect(model.importOutside([run]) == 0)
        model.reload()
        #expect(model.activities.count == 1)
    }

    @Test("A workout from Health deleted here stays deleted when Health reports it again")
    func deletedImportStaysDeleted() {
        let app = TestApp()
        let model = app.onboarded()
        let run = workout(hoursAgo: 20)
        model.importOutside([run])
        model.reload()
        model.delete(activity: run.id)
        #expect(model.activities.isEmpty)
        model.importOutside([run])
        model.reload()
        #expect(model.activities.isEmpty)
        #expect(app.model().activities.isEmpty)
    }

    @Test("Manual activities aren't taken for Health imports")
    func manualActivitiesIgnored() {
        let model = TestApp().onboarded()
        let manual = ActivityLog(type: .bjj, start: Date().addingTimeInterval(-7_200), minutes: 60)
        #expect(model.importOutside([manual]) == 0)
        model.save(activity: manual)
        #expect(model.activities.map(\.id) == [manual.id])
    }
}
