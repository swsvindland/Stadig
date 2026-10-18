import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// The analysis behind the calendar and today's session: which block is current, when a deload
/// happens, how a vacation moves things, and what counts toward Discipline.
@Suite("Analysis")
struct AnalysisTests {
    let gym = Gym.preset(.fullGym, unit: .kg)

    func state(
        _ mesocycles: [Mesocycle], today: Day, sessions: [SessionRecord] = [], lifeModes: [LifeModePeriod] = [],
        recovery: [RecoveryDay] = [], profile: SharedProfile = Fixture.profile(), settings: LiftSettings = LiftSettings()
    ) -> LiftState {
        LiftState(
            profile: profile, settings: settings, gym: gym, catalog: Fixture.catalog, sessions: sessions, mesocycles: mesocycles,
            lifeModes: lifeModes, recovery: recovery, bodyweightKg: 80, today: today)
    }

    /// Today's session as the app plans it: from the analysis's next session.
    func plan(_ a: LiftAnalysis, on day: Day) throws -> SessionPlan {
        let next = try #require(a.next)
        let context = PlanningContext(
            catalog: Fixture.catalog, gym: gym, profile: Fixture.profile(), settings: LiftSettings(), trust: a.trust,
            phase: a.phase, life: a.life, history: a.history, bodyweightKg: 80, enduranceScore: nil,
            sessionIndexInWeek: next.doneThisWeek)
        return SessionPlanner.plan(next.day, of: next.mesocycle, on: day, context: context)
    }

    @Test("a next block accepted during the deload waits for its start, and the check-in stays")
    func plannedAhead() throws {
        let current = ProgramGenerator.generate(Fixture.input(Fixture.profile()))
        var input = Fixture.input(Fixture.profile())
        input.start = current.block.end.adding(days: 1)
        let following = ProgramGenerator.generate(input)
        let friday = current.block.end.adding(days: -2)
        let a = Analyst.analyse(state([current, following], today: friday))
        #expect(a.mesocycle?.id == current.id)
        #expect(a.upcoming?.id == following.id)
        #expect(a.next?.mesocycle.id == current.id)
        let today = try plan(a, on: friday)
        #expect(today.deload && today.checkIn)
        #expect(a.actions.contains { $0.kind == .checkIn })
        #expect(a.calendar.currentBlock == current.block.range)
        #expect(a.calendar.checkIns.contains(current.block.end))
        #expect(a.calendar.deloads.contains { $0.start == following.block.effectiveDeloadStart }, "the next block's deload is published too")

        let monday = Analyst.analyse(state([current, following], today: following.block.start))
        #expect(monday.mesocycle?.id == following.id && monday.upcoming == nil)
        #expect(try !plan(monday, on: following.block.start).deload)
    }

    /// Two beat-up sessions in the last few days and under five and a half hours of sleep all week:
    /// overreached, so the Fatigue Budget calls for an early deload.
    func beatUp(_ m: Mesocycle, on today: Day) -> LiftState {
        let sessions = [3, 1].map { daysAgo in
            let start = today.adding(days: -daysAgo).date().addingTimeInterval(18 * 3600)
            return SessionRecord(
                start: start, end: start.addingTimeInterval(3600), title: m.days[0].name, mesocycleID: m.id, dayID: m.days[0].id,
                feedback: SessionFeedback(soreness: 3, energy: 1))
        }
        return state([m], today: today, sessions: sessions, recovery: (0..<7).map { RecoveryDay(day: today.adding(days: -$0), sleepHours: 5) })
    }

    @Test("an early deload is offered after two loading weeks, and is the plan only once it's taken")
    func earlyDeload() throws {
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile()))
        let week2 = m.block.start.adding(weeks: 2).adding(days: 2)
        let a = Analyst.analyse(beatUp(m, on: week2))
        #expect(a.fatigue.action == .deloadEarly)
        #expect(a.actions.contains { $0.kind == .deloadEarly })
        let suggested = try #require(a.suggestedDeload)
        #expect(suggested.week(of: week2) == .deload)
        // Until it's taken, the block, the published calendar and today's session all agree: loading.
        #expect(a.block?.week(of: week2) == .loading(2))
        #expect(!a.calendar.deloads.contains { $0.contains(week2) })
        #expect(try !plan(a, on: week2).deload)

        var taken = m
        taken.block.deloadStart = suggested.deloadStart
        taken.block.endOverride = suggested.endOverride
        let after = Analyst.analyse(beatUp(taken, on: week2))
        #expect(after.block?.week(of: week2) == .deload)
        #expect(after.calendar.deloads.contains { $0.contains(week2) })
        #expect(try plan(after, on: week2).deload)
        #expect(!after.actions.contains { $0.kind == .deloadEarly })

        // In the first two weeks it isn't offered, however beat up.
        let week1 = m.block.start.adding(weeks: 1).adding(days: 2)
        let early = Analyst.analyse(beatUp(m, on: week1))
        #expect(early.fatigue.action == .deloadEarly)
        #expect(early.suggestedDeload == nil)
        #expect(!early.actions.contains { $0.kind == .deloadEarly })
    }

    @Test("taking the early deload in a block a vacation pushed back puts the deload on today")
    func earlyDeloadAfterAPushedStart() throws {
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile()))
        // A trip in the first days: the block starts ten days late, after it.
        let trip = LifeModePeriod(kind: .vacation, start: m.block.start.adding(days: 2), end: m.block.start.adding(days: 9), createdBy: .liftTrack)
        let today = m.block.start.adding(days: 10).adding(weeks: 2).adding(days: 2)
        func analyse(_ m: Mesocycle) -> LiftAnalysis {
            var s = beatUp(m, on: today)
            s.lifeModes = [trip]
            return Analyst.analyse(s)
        }
        let a = analyse(m)
        #expect(a.block?.start == m.block.start.adding(days: 10))
        #expect(a.block?.week(of: today) == .loading(2))
        #expect(a.actions.contains { $0.kind == .deloadEarly })
        let suggested = try #require(a.suggestedDeload)
        #expect(suggested.start == m.block.start, "in the stored block's dates")

        // Saved either way the app might: the deload dates onto the stored block, or the whole block.
        var dates = m
        dates.block.deloadStart = suggested.deloadStart
        dates.block.endOverride = suggested.endOverride
        var whole = m
        whole.block = suggested
        for taken in [dates, whole] {
            let after = analyse(taken)
            #expect(after.block?.start == a.block?.start)
            #expect(after.block?.week(of: today) == .deload)
            #expect(after.calendar.deloads.contains { $0.contains(today) })
            #expect(try plan(after, on: today).deload)
            #expect(!after.actions.contains { $0.kind == .deloadEarly })
        }
    }

    @Test("a next block planned twice for one start: the later plan is the one coming, and the one that starts")
    func plannedTwiceAhead() throws {
        let current = ProgramGenerator.generate(Fixture.input(Fixture.profile()))
        var input = Fixture.input(Fixture.profile())
        input.start = current.block.end.adding(days: 1)
        var first = ProgramGenerator.generate(input)
        first.createdAt = Fixture.start.date()
        var second = ProgramGenerator.generate(input)
        second.createdAt = Fixture.start.date().addingTimeInterval(60)
        for order in [[current, first, second], [second, current, first]] {
            let friday = Analyst.analyse(state(order, today: current.block.end.adding(days: -2)))
            #expect(friday.mesocycle?.id == current.id)
            #expect(friday.upcoming?.id == second.id)
            let monday = Analyst.analyse(state(order, today: input.start))
            #expect(monday.mesocycle?.id == second.id && monday.upcoming == nil)
        }
        // Before anything has started, likewise.
        let before = Analyst.analyse(state([first, second], today: current.block.start))
        #expect(before.mesocycle?.id == second.id && before.upcoming == nil)
    }

    @Test("a vacation moves today's session the way it moves the calendar")
    func vacationReshapesTheSessions() throws {
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile()))
        // Eight days in the first week: the block starts after the trip.
        let trip = LifeModePeriod(kind: .vacation, start: m.block.start.adding(days: 2), end: m.block.start.adding(days: 9), createdBy: .liftTrack)
        for offset in [10, 17, 35, 45, 50] {
            let day = m.block.start.adding(days: offset)
            let a = Analyst.analyse(state([m], today: day, lifeModes: [trip]))
            let block = try #require(a.block)
            #expect(block.start == trip.end?.adding(days: 1))
            #expect(a.next?.mesocycle.block == block)
            #expect(a.mesocycle?.block == m.block, "the stored block is kept as it was")
            let today = try plan(a, on: day)
            #expect(today.deload == (block.week(of: day) == .deload), "day \(offset)")
            if case .loading(let week) = block.week(of: day) { #expect(today.week == week, "day \(offset)") }
        }
        // The assessment counts its weeks from the moved start too.
        let assessment = ProgramGenerator.generate(Fixture.input(Fixture.profile(), kind: .assessment))
        let a = Analyst.analyse(state([assessment], today: assessment.block.start.adding(days: 12), lifeModes: [trip]))
        #expect(a.assessment?.week == 1)
    }

    @Test("sessions from before the four-week window don't credit the days in it")
    func adherenceAtTheWindowEdge() throws {
        // Mondays, Wednesdays and Fridays; today is a Wednesday, so the window opens on a Thursday.
        let profile = Fixture.profile(days: 3)
        let today = Fixture.start.adding(days: 37)
        #expect(today.weekday == .wednesday)
        let window = Discipline.window(ending: today)
        #expect(window.start.weekday == .thursday)
        // The Monday and Wednesday just before it were done; that Friday was missed.
        let sessions = [-3, -1].map { offset in
            let start = window.start.adding(days: offset).date().addingTimeInterval(18 * 3600)
            return SessionRecord(start: start, end: start.addingTimeInterval(3600), title: "Full body A")
        }
        let s = state([], today: today, sessions: sessions, profile: profile, settings: LiftSettings(assessmentStart: Fixture.start))
        let items = Analyst.adherenceItems(s, sessions: sessions, block: nil, today: today)
        let friday = try #require(items.first { $0.day == window.start.adding(days: 1) })
        #expect(friday.done == false)
    }

    @Test("on the day the program starts, declared classes have nothing to count yet")
    func noClassesBeforeTheStart() {
        let bjj = RecurringActivity(activity: .bjj, weekdays: Weekday.allCases, minutes: 60, intensity: 6)
        let profile = Fixture.profile(recurring: [bjj])
        let s = state([], today: Fixture.start, profile: profile, settings: LiftSettings(assessmentStart: Fixture.start))
        let items = Analyst.adherenceItems(s, sessions: [], block: nil, today: Fixture.start)
        #expect(!items.contains { $0.kind == .declaredClass }, "\(items.map(\.day))")
    }

    @Test("needing less help on assisted pull-ups reads as getting stronger")
    func assistedLiftsTrendUp() {
        let id = "assisted-pull-up"
        #expect(Fixture.catalog.resolve(id).loadBasis == .assisted)
        let sessions = (0..<8).map { week in
            let start = Fixture.start.adding(weeks: week).date().addingTimeInterval(18 * 3600)
            let assistance = 40 - Double(week) * 1.25
            let sets = (0..<3).map {
                LoggedSet(
                    exerciseID: id, date: start.addingTimeInterval(Double($0) * 180), loadKg: assistance, reps: 8, rating: .orange,
                    bodyweightKg: 80)
            }
            return SessionRecord(
                start: start, end: start.addingTimeInterval(3600), title: "Pull",
                exercises: [ExerciseLog(exerciseID: id, sets: sets)])
        }
        let a = Analyst.analyse(state([], today: Fixture.start.adding(weeks: 8), sessions: sessions))
        #expect(Analyst.strengthTrend(a, catalog: Fixture.catalog) == .onPace)
    }

    @Test("a weight typed on today's tape beats an old one from Health, for strength and physique alike")
    func newestBodyweight() {
        let today = Fixture.start
        let tape = BodyMeasurements(day: today, weightKg: 88, bodyFatPercent: 20, waistCm: 90)
        func state(health: Double?, measured date: Date?, tape entries: [BodyMeasurements] = [tape]) -> LiftState {
            LiftState(
                profile: Fixture.profile(), settings: LiftSettings(), gym: gym, catalog: Fixture.catalog, measurements: entries,
                bodyweightKg: health, bodyweightDate: date, today: today)
        }
        let monthsAgo = state(health: 80, measured: today.adding(days: -120).date().addingTimeInterval(7 * 3600))
        #expect(monthsAgo.measuredBodyweight == 88 && monthsAgo.effectiveBodyweight == 88)
        #expect(Analyst.analyse(monthsAgo).physique.latest?.weightKg == 88, "FFMI from the weight typed today")
        // This morning's weigh-in is as new as the tape: Health's, from the scale.
        let thisMorning = state(health: 87.4, measured: today.date().addingTimeInterval(7 * 3600))
        #expect(thisMorning.effectiveBodyweight == 87.4 && Analyst.analyse(thisMorning).physique.latest?.weightKg == 87.4)
        // A tape entry from before Health's weight is older news.
        let lastWeek = BodyMeasurements(day: today.adding(days: -7), weightKg: 90)
        #expect(state(health: 87.4, measured: today.adding(days: -1).date(), tape: [lastWeek]).effectiveBodyweight == 87.4)
        // When Health's date isn't known it stands as current, as it always has.
        #expect(state(health: 80, measured: nil).effectiveBodyweight == 80)
        #expect(state(health: nil, measured: nil).effectiveBodyweight == 88)
        let neither = state(health: nil, measured: nil, tape: [])
        #expect(neither.measuredBodyweight == nil && neither.effectiveBodyweight == 80)
    }
}
