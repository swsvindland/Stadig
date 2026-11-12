import ExerciseLibrary
import Foundation
import HubEngine
import LiftEngine
import SystemCore
import SystemStore
import Testing

@testable import LiftTrack

/// What Today's week strip, the session's dock and Your shape read from the model.
@MainActor
struct TodayAndShapeTests {
    @Test("The week strip is this week from Monday, with today and the training days still to come")
    func weekStrip() {
        let model = TestApp().onboarded()
        let days = model.weekStrip
        #expect(days.count == 7)
        #expect(days.first?.day.weekday == .monday)
        #expect(days.filter(\.isToday).map(\.day) == [model.today])
        let training = Set(model.profile?.schedule.trainingDays ?? [])
        for day in days {
            #expect(day.planned == (!day.trained && day.day >= model.today && training.contains(day.day.weekday)), "\(day.day)")
        }
    }

    @Test("Your shape has Stadig Lift's scores, and Stadig Macro's once it publishes")
    func stats() throws {
        let app = TestApp()
        let model = app.model()
        SampleData.seedIfEmpty(model)
        #expect(model.stats.map(\.stat) == StatsBoard.shown)
        #expect(!model.stats.contains { $0.apps.contains(.macroTrack) })
        let strength = try #require(model.stats.first { $0.stat == .strength })
        #expect(strength.apps == [.liftTrack])
        #expect(strength.score != nil)
        #expect(model.stats.first { $0.stat == .vitality }?.score == nil)

        let macro = AppSummary(
            app: .macroTrack, updated: Date(),
            stats: [StatReading(stat: .vitality, score: 72, label: "Logged 26 of the last 28 days", trend: .onPace)])
        try app.shared.write(macro, to: .summary(.macroTrack), by: .macroTrack)
        model.readShared()
        let vitality = try #require(model.stats.first { $0.stat == .vitality })
        #expect(vitality.score == 72)
        #expect(vitality.apps == [.macroTrack])
    }

    @Test("Last time is the same set in the last session before today, or that session's last")
    func lastTime() throws {
        let model = TestApp().model()
        SampleData.seedIfEmpty(model)
        let analysis = try #require(model.analysis)
        let id = try #require(analysis.history.keys.sorted().first { key in analysis.history[key]?.contains { $0.kind != .warmup } == true })
        let exercise = model.catalog.resolve(id)
        let work = (analysis.history[id] ?? []).filter { $0.kind != .warmup && Day($0.date) < model.today }
        let lastDay = try #require(work.map { Day($0.date) }.max())
        let session = work.filter { Day($0.date) == lastDay }
        #expect(model.lastTime(exercise, setNumber: 1)?.id == session.first?.id)
        #expect(model.lastTime(exercise, setNumber: 99)?.id == session.last?.id)
    }
}
