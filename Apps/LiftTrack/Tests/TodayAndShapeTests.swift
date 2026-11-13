import ExerciseLibrary
import Foundation
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

    @Test("Today's card counts the session's lifting sets, as the summary does, not its drills")
    func todaysSetsAreLiftingSets() throws {
        let model = TestApp().model()
        SampleData.seedIfEmpty(model)
        let plan = try #require(model.plan())
        let lifting = plan.items.filter(\.isStrength).reduce(0) { $0 + $1.workSets.count }
        #expect(lifting > 0)
        #expect(plan.items.contains { !$0.isStrength && !$0.workSets.isEmpty }, "the sample's session has drills with sets of their own")
        #expect(HeroLine.contents(plan: plan, catalog: model.catalog).hasSuffix("· \(lifting) sets"))
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

    @Test("Publishing records today's scores in the store and the shared file; someone new sees no change")
    func scoresAreRecorded() throws {
        let app = TestApp()
        let model = app.onboarded()
        let recorded = try #require(app.shared.read(.scores(.liftTrack)))
        let published = try #require(app.shared.read(.summary(.liftTrack)))
        #expect(!published.stats.isEmpty)
        #expect(app.store.all(ScoreDayRecord.self).map(\.day) == [model.today])
        for reading in published.stats {
            let score = try #require(reading.score)
            #expect(recorded.points(reading.stat) == [ScorePoint(day: model.today, score: (score * 10).rounded() / 10)], "\(reading.stat)")
        }
        #expect(model.stats.allSatisfy { $0.change == nil }, "nothing to measure from on the first day")
        #expect(model.earlierShape == nil)
        #expect(model.physiqueChange == nil)
        // A relaunch with nothing changed writes nothing.
        let written = app.shared.envelope(.scores(.liftTrack))?.writtenAt
        _ = app.model()
        #expect(app.shared.envelope(.scores(.liftTrack))?.writtenAt == written)
    }

    @Test("A month of recorded scores says how each moved, here and in Stadig Macro's numbers too")
    func scoresHaveMoved() throws {
        let app = TestApp()
        let model = app.model()
        SampleData.seedIfEmpty(model)
        let strength = try #require(model.stats.first { $0.stat == .strength }?.change)
        #expect(strength.direction == .up)
        #expect(model.stats.first { $0.stat == .agility }?.change?.short == "steady")
        let monthAgo = model.today.adding(months: -1)
        try app.shared.write(
            AppSummary(
                app: .macroTrack, updated: Date(),
                stats: [StatReading(stat: .vitality, score: 72, label: "Logged 26 of the last 28 days", trend: .onPace)]),
            to: .summary(.macroTrack), by: .macroTrack)
        try app.shared.write(
            ScoreHistory(app: .macroTrack, stats: [.vitality: [ScorePoint(day: monthAgo, score: 73.2)]]), to: .scores(.macroTrack), by: .macroTrack)
        model.readShared()
        #expect(model.stats.first { $0.stat == .vitality }?.change?.short == "\u{2212}1")
    }

    @Test("A day another device recorded, arriving through iCloud, joins the history and its change")
    func anotherDevicesDays() throws {
        let app = TestApp()
        let model = app.onboarded()
        let (stat, points) = try #require(app.shared.read(.scores(.liftTrack))?.stats.first)
        let today = try #require(points.last)
        let earlier = model.today.adding(days: -9)
        app.store.save(ScoreDayRecord(day: earlier, scores: [stat: today.score - 3], updatedAt: Date()))
        model.reloadIfChanged()
        #expect(app.shared.read(.scores(.liftTrack))?.points(stat) == [ScorePoint(day: earlier, score: today.score - 3), today])
        #expect(model.stats.first { $0.stat == stat }?.change?.whole == 3)
    }

    @Test("Progress's Year measures each score from a year ago; its Month, as everywhere, from a month ago")
    func scoresOverTheYear() throws {
        let app = TestApp()
        let model = app.onboarded()
        let (stat, points) = try #require(app.shared.read(.scores(.liftTrack))?.stats.first)
        let today = try #require(points.last)
        // Away from whichever end is nearer, so neither reading is cut at 0 or 100.
        let sign: Double = today.score > 50 ? -1 : 1
        app.store.save(ScoreDayRecord(day: model.today.adding(days: -370), scores: [stat: today.score + sign * 12], updatedAt: Date()))
        app.store.save(ScoreDayRecord(day: model.today.adding(days: -20), scores: [stat: today.score + sign * 4], updatedAt: Date()))
        model.reloadIfChanged()
        #expect(model.changes(over: .month)[stat]?.whole == -Int(sign) * 4)
        let year = try #require(model.changes(over: .year)[stat])
        #expect(year.whole == -Int(sign) * 12)
        #expect(year.period == .thisYear)
        #expect(Array(model.changes(over: .year).keys) == [stat], "the rest have only today's reading")
        #expect(model.changes(over: .month)[stat] == model.stats.first { $0.stat == stat }?.change)
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
