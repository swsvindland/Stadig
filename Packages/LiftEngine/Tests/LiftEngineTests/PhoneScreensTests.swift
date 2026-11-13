import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// The iPhone's Plan lists this week's sessions, and the summary sets a finished session against its
/// plan and the last time.
@Suite("Phone screens")
struct PhoneScreensTests {
    /// A session of the program's day `index`, done on `day` at six in the evening, an hour long.
    private func session(_ m: Mesocycle, index: Int, on day: Day, sets: [LoggedSet] = []) -> SessionRecord {
        let start = day.date().addingTimeInterval(18 * 3600)
        return SessionRecord(
            start: start, end: start.addingTimeInterval(55 * 60), title: m.days[index].name, mesocycleID: m.id, dayID: m.days[index].id,
            exercises: sets.isEmpty ? [] : [ExerciseLog(exerciseID: "barbell-bench-press", sets: sets)])
    }

    private func bench(_ load: Double, reps: Int, on day: Day) -> LoggedSet {
        LoggedSet(exerciseID: "barbell-bench-press", date: day.date(), kind: .working, loadKg: load, reps: reps, targetReps: reps, rating: .orange)
    }

    @Test("this week: the sessions done, then today's and the rest in rotation on the training days left")
    func thisWeek() throws {
        // Four days a week: Monday, Tuesday, Thursday and Friday. Monday and Tuesday done; it's Thursday.
        let profile = Fixture.profile(days: 4)
        let m = ProgramGenerator.generate(Fixture.input(profile))
        let monday = m.block.start.startOfWeek.adding(weeks: 1)
        let records = [session(m, index: 0, on: monday), session(m, index: 1, on: monday.adding(days: 1))]
        let thursday = monday.adding(days: 3)
        let next = Analyst.nextSession(m, sessions: records, profile: profile, today: thursday)
        let rows = ThisWeek.sessions(next: next, records: records, trainingDays: profile.schedule.trainingDays, today: thursday)
        #expect(rows.map(\.day) == [monday, monday.adding(days: 1), thursday, thursday.adding(days: 1)])
        #expect(rows.map(\.state) == [.done, .done, .today, .planned])
        #expect(rows.map(\.title) == [0, 1, 2, 3].map { m.days[$0 % m.days.count].name })
        #expect(rows[0].minutes == 55)
        #expect(rows[2].minutes == m.days[2 % m.days.count].minutes)
        #expect(rows[2].dayID == m.days[2 % m.days.count].id)

        // On Wednesday, a rest day, Thursday's is next and nothing is today's.
        let wednesday = monday.adding(days: 2)
        let restDay = Analyst.nextSession(m, sessions: records, profile: profile, today: wednesday)
        let fromWednesday = ThisWeek.sessions(next: restDay, records: records, trainingDays: profile.schedule.trainingDays, today: wednesday)
        #expect(fromWednesday.map(\.state) == [.done, .done, .planned, .planned])

        // Today's done: it's listed done, and the plan goes on from tomorrow.
        let doneToday = records + [session(m, index: 2, on: thursday)]
        let after = Analyst.nextSession(m, sessions: doneToday, profile: profile, today: thursday)
        let rest = ThisWeek.sessions(next: after, records: doneToday, trainingDays: profile.schedule.trainingDays, today: thursday)
        #expect(rest.map(\.state) == [.done, .done, .done, .planned])
        #expect(rest.last?.day == thursday.adding(days: 1))

        // Last week's sessions aren't this week's; with no block there's nothing still to come.
        let lastWeek = [session(m, index: 0, on: monday.adding(days: -7))]
        #expect(ThisWeek.sessions(next: nil, records: lastWeek, trainingDays: profile.schedule.trainingDays, today: thursday).isEmpty)
    }

    @Test("a missed day doesn't fill the week past Sunday")
    func missedDays() throws {
        let profile = Fixture.profile(days: 4)
        let m = ProgramGenerator.generate(Fixture.input(profile))
        // Nothing done by Friday: only Friday is left of the four.
        let friday = m.block.start.startOfWeek.adding(weeks: 1).adding(days: 4)
        let next = Analyst.nextSession(m, sessions: [], profile: profile, today: friday)
        let rows = ThisWeek.sessions(next: next, records: [], trainingDays: profile.schedule.trainingDays, today: friday)
        #expect(rows.map(\.day) == [friday])
        #expect(rows.first?.title == m.days[0].name)
    }

    @Test("the summary's numbers: minutes against the plan, sets against the plan's, and lifted against the same day last time")
    func tally() throws {
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile()))
        let day = m.block.start.adding(weeks: 1)
        let before = session(m, index: 0, on: day.adding(days: -7), sets: [bench(80, reps: 5, on: day.adding(days: -7))])
        let other = session(m, index: 1, on: day.adding(days: -2), sets: [bench(100, reps: 5, on: day.adding(days: -2))])
        let today = session(m, index: 0, on: day, sets: [bench(80, reps: 5, on: day), bench(80, reps: 5, on: day)])
        let tally = SessionTally(today, plannedMinutes: 57, plannedSets: 3, earlier: [before, other, today])
        #expect(tally.minutes == 55)
        #expect(tally.underPlan == 2)
        #expect(tally.sets == 2)
        #expect(tally.plannedSets == 3)
        #expect(tally.liftedKg == 800)
        // Against the same program day a week ago (400 kg), not the other day in between.
        #expect(tally.liftedChange == 1)

        // A first time has nothing to compare with.
        let first = SessionTally(before, plannedMinutes: nil, plannedSets: nil, earlier: [before, other, today])
        #expect(first.liftedChange == nil)
        #expect(first.underPlan == nil)
    }
}
