import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// What the iPad and Mac screens are built from: the block laid out week by week, an exercise's own
/// history, the History table's rows, and a session reordered by dragging.
@Suite("Program layout")
struct ProgramLayoutTests {
    @Test func setsRunWeekByWeekThenTheDeload() throws {
        let block = TrainingBlock(kind: .standard, start: Fixture.start, loadingWeeks: 4)
        let slot = SlotPlan(exerciseID: "barbell-back-squat", role: .main, sets: [3, 3, 4, 4], repRange: RepRange(5, 8), restSeconds: 180)
        let weeks = ProgramLayout.setsByWeek(slot, block: block)
        #expect(weeks.map(\.sets) == [3, 3, 4, 4, 2])
        #expect(weeks.map(\.isDeload) == [false, false, false, false, true])
        #expect(ProgramLayout.summary(weeks) == "3·3·4·4 · 2")

        // A plan shorter than the block repeats its last week; an odd last week rounds the deload up.
        let short = SlotPlan(exerciseID: "db-curl", role: .accessory, sets: [3], repRange: RepRange(10, 15), restSeconds: 60)
        #expect(ProgramLayout.setsByWeek(short, block: block).map(\.sets) == [3, 3, 3, 3, 2])
        // Drills and conditioning aren't counted in sets.
        let drill = SlotPlan(exerciseID: "hip-90-90", role: .mobility, sets: [], repRange: RepRange(1, 1), restSeconds: 0)
        #expect(ProgramLayout.setsByWeek(drill, block: block).isEmpty)
    }

    @Test func theDeloadHalvesSetsAsTheSessionPrescribesThem() throws {
        // The program's deload column must say what the deload session will actually give.
        let exercise = try #require(Fixture.catalog["barbell-bench-press"])
        let history = (0..<3).map { week in
            LoggedSet(
                exerciseID: exercise.id, date: Fixture.start.adding(weeks: week).date(), kind: .working, loadKg: 90, reps: 6,
                targetReps: 6, rating: .orange)
        }
        for lastWeek in 1...6 {
            let context = ProgressionContext(
                exercise: exercise, increments: Gym.preset(.fullGym, unit: .kg).increments(for: exercise.equipment),
                trust: TrustState(prior: 0.5), phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: history)
            let deload = Progression.prescribe(SlotTarget(sets: lastWeek, repRange: RepRange(5, 8), targetRIR: 2, deload: true), context)
            #expect(deload.sets.count == ProgramLayout.deloadSets(lastLoadingWeek: lastWeek), "\(lastWeek) sets")
        }
    }

    @Test func theCalendarMarksTrainingDaysVacationsTheDeloadAndToday() throws {
        // Starts on a Monday: four loading weeks, then the deload.
        let block = TrainingBlock(kind: .standard, start: Fixture.start, loadingWeeks: 4)
        let trainingDays: Set<Weekday> = [.monday, .wednesday, .friday]
        let trained: Set<Day> = [Fixture.start, Fixture.start.adding(days: 2)]
        let away = DayRange(Fixture.start.adding(days: 14), Fixture.start.adding(days: 18))
        let today = Fixture.start.adding(days: 9)
        let weeks = ProgramLayout.calendar(block: block, trainingDays: trainingDays, trained: trained, vacations: [away], today: today)
        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.days.count == 7 })
        #expect(weeks.map(\.week) == [.loading(0), .loading(1), .loading(2), .loading(3), .deload])
        let days = weeks.flatMap(\.days)
        #expect(days.filter(\.isToday).map(\.day) == [today])
        #expect(days.filter(\.trained).map(\.day) == Array(trained).sorted())
        // No training expected on a vacation day, even a Monday.
        #expect(days.first { $0.day == away.start }?.vacation == true)
        #expect(days.first { $0.day == away.start }?.training == false)
        #expect(days.filter(\.training).allSatisfy { trainingDays.contains($0.day.weekday) && !$0.vacation })
        // The check-in is the deload's last day.
        #expect(days.filter(\.checkIn).map(\.day) == [block.end])
    }

    @Test func aBlockCutShortLeavesItsLastDaysOutside() throws {
        var block = TrainingBlock(kind: .standard, start: Fixture.start, loadingWeeks: 4)
        block.endOverride = Fixture.start.adding(days: 30)
        let weeks = ProgramLayout.calendar(block: block, trainingDays: [.monday], trained: [], vacations: [], today: Fixture.start)
        let last = try #require(weeks.last)
        #expect(last.days.filter(\.inBlock).map(\.day).last == block.end)
        #expect(last.days.filter { !$0.inBlock }.allSatisfy { !$0.training })
    }
}

@Suite("An exercise's own history")
struct ExerciseRecordTests {
    func set(_ day: Day, hour: Double = 18, load: Double, reps: Int, kind: SetKind = .working, rating: SetRating? = .orange) -> LoggedSet {
        LoggedSet(
            exerciseID: "barbell-bench-press", date: day.date().addingTimeInterval(hour * 3600), kind: kind, loadKg: load, reps: reps,
            targetReps: reps, rating: rating, bodyweightKg: 80)
    }

    @Test func sessionsBestSetsAndTheTrend() throws {
        let exercise = try #require(Fixture.catalog["barbell-bench-press"])
        let trust = TrustState(prior: 0.5)
        let sets = [
            set(Fixture.start, load: 60, reps: 5, kind: .warmup, rating: nil), set(Fixture.start, load: 80, reps: 6),
            set(Fixture.start, load: 80, reps: 6),
            set(Fixture.start.adding(days: 7), load: 82.5, reps: 6), set(Fixture.start.adding(days: 7), load: 82.5, reps: 5),
            set(Fixture.start.adding(days: 14), load: 85, reps: 6),
            // Another exercise's set never counts.
            LoggedSet(exerciseID: "barbell-back-squat", date: Fixture.start.date(), kind: .working, loadKg: 140, reps: 5, rating: .orange),
        ]
        let record = ExerciseRecord.of(sets, exercise: exercise, trust: trust)
        #expect(record.sessions == 3)
        #expect(record.lastDone == Fixture.start.adding(days: 14))
        #expect(record.trend.map(\.day) == [Fixture.start, Fixture.start.adding(days: 7), Fixture.start.adding(days: 14)])
        #expect(record.trend.map(\.e1rm) == record.trend.map(\.e1rm).sorted())
        // One best set per session, best first: the heaviest day leads, and the warm-up never shows.
        #expect(record.bestSets.map(\.set.loadKg) == [85, 82.5, 80])
        #expect(record.bestSets.allSatisfy { $0.set.kind != .warmup })
        let change = try #require(record.change)
        #expect(change > 0)
        #expect(
            record.current
                == StrengthEstimator.current(sets.filter { $0.exerciseID == exercise.id && $0.kind != .warmup }, basis: .external, trust: trust))
    }

    @Test func nothingDoneYetIsEmpty() throws {
        let exercise = try #require(Fixture.catalog["barbell-bench-press"])
        let record = ExerciseRecord.of([], exercise: exercise, trust: TrustState(prior: 0.5))
        #expect(record.isEmpty)
        #expect(record.trend.isEmpty && record.bestSets.isEmpty && record.current == nil && record.change == nil)
    }

    @Test func timedWorkRanksByRepsWithoutAnEstimate() throws {
        let plank = try #require(Fixture.catalog["plank"])
        let sets = [10, 30, 20].enumerated().map { index, reps in
            LoggedSet(exerciseID: plank.id, date: Fixture.start.adding(days: index * 7).date(), kind: .working, loadKg: 0, reps: reps)
        }
        let record = ExerciseRecord.of(sets, exercise: plank, trust: TrustState(prior: 0.5))
        #expect(record.sessions == 3)
        #expect(record.bestSets.map(\.set.reps) == [30, 20, 10])
        #expect(record.trend.isEmpty)
    }
}

@Suite("History rows")
struct HistoryRowTests {
    @Test func sessionsAndActivitiesNewestFirstWithTheirColumns() throws {
        let catalog = Fixture.catalog
        let monday = Fixture.start.date().addingTimeInterval(18 * 3600)
        let bench = LoggedSet(exerciseID: "barbell-bench-press", date: monday, kind: .working, loadKg: 90, reps: 5, rating: .orange)
        let curl = LoggedSet(exerciseID: "db-curl", date: monday, kind: .working, loadKg: 16, reps: 12, rating: .orange)
        let warmup = LoggedSet(exerciseID: "barbell-bench-press", date: monday, kind: .warmup, loadKg: 120, reps: 1)
        let session = SessionRecord(
            start: monday, end: monday.addingTimeInterval(55 * 60), title: "Upper A",
            exercises: [
                ExerciseLog(exerciseID: "barbell-bench-press", sets: [warmup, bench]), ExerciseLog(exerciseID: "db-curl", sets: [curl]),
            ], device: "Mac")
        let bjj = ActivityLog(
            type: .bjj, start: monday.addingTimeInterval(86_400), minutes: 75, intensity: 7, source: .health(UUID(), sourceName: "Strava"))
        let rows = HistoryRow.rows(sessions: [session], activities: [bjj], catalog: catalog, trust: TrustState(prior: 0.5))
        #expect(rows.map(\.id) == [bjj.id, session.id])

        let lifting = try #require(rows.last)
        #expect(lifting.isSession && lifting.name == "Upper A" && lifting.minutes == 55)
        #expect(lifting.workSets == 2)
        #expect(lifting.source == "Mac")
        // The heaviest work by estimate, never a warm-up however heavy.
        #expect(lifting.topSet?.set.exerciseID == "barbell-bench-press")
        #expect(lifting.topSet?.set.loadKg == 90)
        #expect(lifting.topSetE1RM > 90)

        let outside = try #require(rows.first)
        #expect(!outside.isSession && outside.kind == .activity(.bjj))
        #expect(outside.workSets == 0 && outside.topSet == nil && outside.topSetE1RM == 0)
        #expect(outside.source == "Health · Strava" && outside.effort == 7)
    }

    @Test func searchMatchesTheNameAndTheExercises() throws {
        let start = Fixture.start.date()
        let session = SessionRecord(
            start: start, end: start.addingTimeInterval(3600), title: "Lower B",
            exercises: [ExerciseLog(exerciseID: "barbell-back-squat", sets: [])])
        let row = try #require(HistoryRow.rows(sessions: [session], activities: [], catalog: Fixture.catalog, trust: TrustState(prior: 0.5)).first)
        #expect(row.matches("lower"))
        #expect(row.matches("back squat"))
        #expect(row.matches(""))
        #expect(!row.matches("bench"))
    }
}

@Suite("Reordering a session")
struct ReorderTests {
    /// A session from a real day, its second and third items made a superset.
    func session() throws -> LiveSession {
        let profile = Fixture.profile()
        let m = ProgramGenerator.generate(Fixture.input(profile))
        let context = PlanningContext(
            catalog: Fixture.catalog, gym: Gym.preset(.fullGym, unit: .kg), profile: profile, settings: LiftSettings(),
            trust: TrustState(experience: .intermediate), phase: .assumedMaintenance, life: LifeModeEffects(), history: [:],
            bodyweightKg: 80, enduranceScore: 50, sessionIndexInWeek: 0)
        var live = LiveSession(plan: SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: context), device: "Test")
        for index in live.items.indices { live.items[index].plan.supersetGroup = nil }
        try #require(live.items.count >= 4)
        live.items[1].plan.supersetGroup = 7
        live.items[2].plan.supersetGroup = 7
        return live
    }

    @Test func aDraggedExerciseLandsWhereItWasDropped() throws {
        var live = try session()
        let ids = live.items.map(\.id)
        let last = live.items.count - 1
        live.move(items: [last], to: 0)
        #expect(live.items.map(\.id) == [ids[last]] + ids.dropLast())
        // What's next follows the order: nothing is done yet, so the first item is.
        #expect(live.current?.item == 0)
        // Back again, to the end.
        live.move(items: [0], to: live.items.count)
        #expect(live.items.map(\.id) == ids)
    }

    @Test func aSupersetMovesWholeAndIsNeverSplit() throws {
        var live = try session()
        let pair = live.items.indices.filter { live.items[$0].plan.supersetGroup == 7 }
        let pairIDs = pair.map { live.items[$0].id }
        // Dragging one half takes the other with it, in order.
        live.move(items: [pair[1]], to: 0)
        #expect(Array(live.items.prefix(2).map(\.id)) == pairIDs)
        // Dropping something between the two lands it after the pair.
        let lastID = live.items[live.items.count - 1].id
        live.move(items: [live.items.count - 1], to: 1)
        #expect(Array(live.items.prefix(3).map(\.id)) == pairIDs + [lastID])
    }

    @Test func aRestCarriesOnAndNothingElseChanges() throws {
        var live = try session()
        live.rest = RestState(
            started: Date(), plan: RestPlan(target: 90, minimum: 60, heartRateGuided: false), itemID: live.items[0].id,
            endsAt: Date().addingTimeInterval(90), preSetHeartRate: nil, filler: nil)
        let before = live.items
        live.move(items: [live.items.count - 1], to: 1)
        #expect(live.rest != nil)
        #expect(Set(live.items.map(\.id)) == Set(before.map(\.id)))
        #expect(live.items.count == before.count)
        // A drop where it already was changes nothing.
        let order = live.items.map(\.id)
        let stamp = live.updatedAt
        live.move(items: [2], to: 2)
        #expect(live.items.map(\.id) == order && live.updatedAt == stamp)
    }
}
