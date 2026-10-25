import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// A word before a heavy session on a long fast that Stadig Macro published: a day or more in by now
/// or by the usual start, not in a deload, and not once the session's done.
@Suite("Fasting and training")
struct FastingTrainingTests {
    let gym = Gym.preset(.fullGym, unit: .kg)
    let mesocycle = ProgramGenerator.generate(Fixture.input(Fixture.profile()))

    func at(_ day: Day, _ hour: Int, _ minute: Int = 0) -> Date { day.at(hour: hour, minute: minute) }

    func session(_ day: Day, _ hour: Int, _ minute: Int = 0) -> SessionRecord {
        let start = at(day, hour, minute)
        return SessionRecord(start: start, end: start.addingTimeInterval(3600), title: "Full body A")
    }

    func analyse(today: Day, now: Date, fast: PublishedFast?, sessions: [SessionRecord] = []) -> LiftAnalysis {
        let nutrition = NutritionSummary(phase: nil, maintenanceKcal: nil, days: [], fast: fast)
        return Analyst.analyse(
            LiftState(
                profile: Fixture.profile(), settings: LiftSettings(), gym: gym, catalog: Fixture.catalog, sessions: sessions,
                mesocycles: [mesocycle], bodyweightKg: 80, nutrition: nutrition, today: today, now: now))
    }

    /// The block's first training day with a session to do, in a loading week.
    func trainingDay() throws -> Day {
        try #require(
            DayRange(mesocycle.block.start, mesocycle.block.start.adding(days: 6)).days.first { day in
                analyse(today: day, now: at(day, 9), fast: nil).next?.scheduledToday == true
            })
    }

    @Test("the usual start is the middle of the last few sessions' times, by their own clock")
    func usualStart() {
        let day = Fixture.start
        #expect(FastingTraining.usualStart(on: day, sessions: []) == nil)
        let sessions = [session(day.adding(days: -5), 17), session(day.adding(days: -3), 18), session(day.adding(days: -1), 18, 30)]
        #expect(FastingTraining.usualStart(on: day, sessions: sessions) == at(day, 18))
    }

    @Test("30 hours into a fast on a training day, before the session: a word, with what to do")
    func deepIntoAFast() throws {
        let day = try trainingDay()
        let fast = PublishedFast(start: at(day.adding(days: -1), 4), goalHours: 48)
        let a = analyse(today: day, now: at(day, 10), fast: fast)
        let note = try #require(a.actions.first { $0.kind == .fasting })
        #expect(note.detail.hasPrefix("You're 30 hours into a fast"))
        #expect(note.action.contains("protein"))
        // Done for today once the session's in.
        let trained = analyse(today: day, now: at(day, 12), fast: fast, sessions: [session(day, 10)])
        #expect(!trained.actions.contains { $0.kind == .fasting })
        // Nothing published, nothing said.
        #expect(!analyse(today: day, now: at(day, 10), fast: nil).actions.contains { $0.kind == .fasting })
    }

    @Test("16 hours in at breakfast, a day by the usual 6 PM session: a word now; with the goal ending first, none")
    func byTheUsualStart() throws {
        let day = try trainingDay()
        let usual = (1...3).map { session(day.adding(days: -$0 * 2), 18) }
        let long = PublishedFast(start: at(day.adding(days: -1), 18), goalHours: 36)
        let note = try #require(analyse(today: day, now: at(day, 10), fast: long, sessions: usual).actions.first { $0.kind == .fasting })
        #expect(note.detail.hasPrefix("You'll be about 24 hours into a fast by your usual start"))
        let short = PublishedFast(start: at(day.adding(days: -1), 18), goalHours: 20)
        #expect(!analyse(today: day, now: at(day, 10), fast: short, sessions: usual).actions.contains { $0.kind == .fasting })
    }

    @Test("a rest day or a deload's lighter session gets nothing")
    func restAndDeload() throws {
        let day = try trainingDay()
        let rest = try #require(
            DayRange(day, day.adding(days: 6)).days.first { analyse(today: $0, now: at($0, 9), fast: nil).next?.scheduledToday == false })
        let fast = PublishedFast(start: at(rest.adding(days: -1), 4), goalHours: 48)
        #expect(!analyse(today: rest, now: at(rest, 10), fast: fast).actions.contains { $0.kind == .fasting })
        let next = try #require(analyse(today: day, now: at(day, 9), fast: nil).next)
        let deepFast = PublishedFast(start: at(day.adding(days: -1), 4), goalHours: 48)
        #expect(FastingTraining.note(fast: deepFast, next: next, deload: true, trainedToday: false, usualStart: nil, now: at(day, 10)) == nil)
        #expect(FastingTraining.note(fast: deepFast, next: next, deload: false, trainedToday: false, usualStart: nil, now: at(day, 10)) != nil)
    }
}
