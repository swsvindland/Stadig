import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// What a finished session taught, for its summary: next time's loads, read from the planner; the
/// rests; the ratings; ranked and capped at the card's four.
@Suite("What a session taught")
struct SessionLessonsTests {
    /// Two days a week, Monday and Thursday, a day each of a two-day full-body program.
    let profile = Fixture.profile(days: 2)
    let m = SessionLessonsTests.program()
    /// The second week's Monday: week 1 of the block.
    let monday = Fixture.start.adding(weeks: 1)

    /// Day A: the row, overhead press and squat as main lifts, then curls, push-ups and a plank; day B
    /// the deadlift and bench. Five loading weeks and a deload.
    static func program() -> Mesocycle {
        let a = PlannedDay(
            name: "Full body A", focus: .full,
            blocks: [
                SessionBlockPlan(
                    kind: .main, minutes: 30,
                    slots: [
                        SlotPlan(exerciseID: "barbell-row", role: .main, sets: [3], repRange: RepRange(6, 10), restSeconds: 150),
                        SlotPlan(exerciseID: "barbell-overhead-press", role: .main, sets: [3], repRange: RepRange(6, 10), restSeconds: 150),
                        SlotPlan(exerciseID: "barbell-back-squat", role: .main, sets: [3], repRange: RepRange(5, 8), restSeconds: 180),
                    ]),
                SessionBlockPlan(
                    kind: .accessory, minutes: 15,
                    slots: [
                        SlotPlan(exerciseID: "db-curl", role: .accessory, sets: [3], repRange: RepRange(8, 12), restSeconds: 90),
                        SlotPlan(exerciseID: "push-up", role: .accessory, sets: [3], repRange: RepRange(8, 15), restSeconds: 90),
                        SlotPlan(exerciseID: "plank", role: .accessory, sets: [3], repRange: RepRange(1, 1), restSeconds: 60, seconds: 45),
                    ]),
            ])
        let b = PlannedDay(
            name: "Full body B", focus: .full,
            blocks: [
                SessionBlockPlan(
                    kind: .main, minutes: 30,
                    slots: [
                        SlotPlan(exerciseID: "conventional-deadlift", role: .main, sets: [3], repRange: RepRange(4, 6), restSeconds: 180),
                        SlotPlan(exerciseID: "barbell-bench-press", role: .main, sets: [3], repRange: RepRange(6, 10), restSeconds: 150),
                    ])
            ])
        return Mesocycle(
            block: TrainingBlock(kind: .standard, start: Fixture.start, loadingWeeks: 5, deloadWeeks: 1), split: .fullBody, days: [a, b],
            priorities: [], rationale: Rationale(headline: ""), minutesPerSession: 60, phase: .assumedMaintenance)
    }

    /// A lift's work sets at one load, two and a half minutes apart, from six in the evening.
    func sets(_ id: String, _ kg: Double, _ reps: [Int], target: Int, _ ratings: [SetRating?], on day: Day, at minute: Int = 0) -> [LoggedSet] {
        let start = day.date().addingTimeInterval(18 * 3600 + Double(minute) * 60)
        return reps.indices.map { i in
            LoggedSet(
                exerciseID: id, date: start.addingTimeInterval(Double(i) * 150), kind: .working, loadKg: kg, reps: reps[i], targetReps: target,
                rating: ratings[min(i, ratings.count - 1)], bodyweightKg: 80, restBeforeSeconds: i == 0 ? nil : 150)
        }
    }

    /// The program's day A done on `day`, with these lifts.
    func session(on day: Day, _ lifts: [[LoggedSet]]) -> SessionRecord {
        let start = day.date().addingTimeInterval(18 * 3600)
        return SessionRecord(
            start: start, end: start.addingTimeInterval(55 * 60), title: m.days[0].name, mesocycleID: m.id, dayID: m.days[0].id,
            exercises: lifts.map { ExerciseLog(slotID: nil, exerciseID: $0[0].exerciseID, sets: $0) })
    }

    /// The lessons as the app reads them once the session is saved, and next time's items.
    func taught(_ record: SessionRecord, unit: WeightUnit = .kg, rest: RestReview? = nil) -> (
        lessons: [SessionLesson], next: [String: PlannedItem]
    ) {
        let state = LiftState(
            profile: profile, settings: LiftSettings(selfReportedPhase: .maintaining), gym: Gym.preset(.fullGym, unit: unit),
            catalog: Fixture.catalog, sessions: [record], mesocycles: [m], bodyweightKg: 80, today: record.day)
        let analysis = Analyst.analyse(state)
        let next = NextTime.items(after: record, state: state, analysis: analysis)
        return (SessionLessons.lessons(record: record, plan: nil, next: next, rest: rest, catalog: Fixture.catalog, unit: unit), next)
    }

    func lesson(_ lessons: [SessionLesson], _ id: String) -> SessionLesson? { lessons.first { $0.exerciseID == id } }

    @Test("next time is the program's next session with the lift, on its training day and week")
    func nextTimeIsTheNextSessionWithTheLift() throws {
        let record = session(on: monday, [sets("barbell-row", 60, [8, 8, 8], target: 8, [.orange], on: monday)])
        let state = LiftState(
            profile: profile, settings: LiftSettings(), gym: Gym.preset(.fullGym, unit: .kg), catalog: Fixture.catalog, sessions: [record],
            mesocycles: [m], bodyweightKg: 80, today: monday)
        let next = try #require(Analyst.analyse(state).next)
        // Day B on Thursday, then day A the Monday after, in the block's next week.
        let upcoming = NextTime.upcoming(after: next, trainingDays: profile.schedule.trainingDays, today: monday)
        #expect(upcoming.map(\.day.name) == ["Full body B", "Full body A"])
        #expect(upcoming.map(\.date) == [monday.adding(days: 3), monday.adding(weeks: 1)])
        #expect(upcoming.map(\.indexInWeek) == [1, 0])
        let row = try #require(taught(record).next["barbell-row"])
        #expect(row.workSets.allSatisfy { $0.targetRIR == Progression.targetRIR(week: 2, of: 5) }, "the week the next row falls in")
    }

    @Test("easy sets move a load up, a held press gets a rep, and a miss brings the squat down, all as the planner has it")
    func loadsInWords() throws {
        let record = session(
            on: monday,
            [
                sets("barbell-row", 60, [11, 11, 11], target: 8, [.green], on: monday),
                sets("barbell-overhead-press", 40, [6, 6, 6], target: 6, [.orange], on: monday, at: 10),
                sets("barbell-back-squat", 100, [4, 4, 4], target: 6, [.red], on: monday, at: 20),
                sets("db-curl", 12, [12, 12, 12], target: 10, [.green], on: monday, at: 30),
            ])
        let (lessons, next) = taught(record)
        // The row, at 2.5 kg steps, moves a step: all it may in one session at maintenance.
        let row = try #require(lesson(lessons, "barbell-row"))
        #expect(row.kind == .up && row.tone == .good)
        #expect(row.title == "Row moves up 2.5 kg next time")
        #expect(row.detail == "All three sets felt easy · 60 → 62.5 kg")
        #expect(next["barbell-row"]?.workSets.first?.loadKg == 62.5)
        // 2.5 kg on 40 is too coarse a step to progress by load: the reps climb first.
        let press = try #require(lesson(lessons, "barbell-overhead-press"))
        #expect(press.kind == .held && press.tone == .ok)
        #expect(press.title == "Overhead press held")
        #expect(press.detail == "Same weight, one more rep · 40 kg × 6, 6, 6")
        #expect(next["barbell-overhead-press"]?.workSets.first?.loadKg == 40)
        #expect(next["barbell-overhead-press"]?.workSets.first?.targetReps == 7)
        // Every squat set missed: the estimate from what was done, with no floor under it.
        let squat = try #require(lesson(lessons, "barbell-back-squat"))
        let squatNext = try #require(next["barbell-back-squat"]?.workSets.first?.loadKg)
        #expect(squat.kind == .missed && squat.tone == .bad)
        #expect(squatNext < 100)
        #expect(squat.title == "Squat comes down \(SessionLessons.number(100 - squatNext)) kg next time")
        #expect(squat.detail == "All three sets fell short · 100 → \(SessionLessons.number(squatNext)) kg")
        // Dumbbells step 2 kg: twelve at the top of the 8–12 range moves the weight and starts the reps again.
        let curl = try #require(lesson(lessons, "db-curl"))
        #expect(curl.title == "Dumbbell Curl moves up 2 kg next time")
        #expect(curl.detail == "12 reps, the top of the range · 12 → 14 kg each")
        // The miss first, then what moves, then the held lift; the accessory last.
        #expect(lessons.map(\.exerciseID) == ["barbell-back-squat", "barbell-row", "barbell-overhead-press", "db-curl"])
    }

    @Test("a miss on a lift that progresses by reps holds it, with the same target")
    func missHolds() throws {
        let record = session(on: monday, [sets("barbell-overhead-press", 40, [5, 5, 4], target: 7, [.red], on: monday)])
        let (lessons, next) = taught(record)
        let press = try #require(lessons.first)
        #expect(next["barbell-overhead-press"]?.workSets.first?.loadKg == 40)
        #expect(press.kind == .missed && press.tone == .bad)
        #expect(press.title == "Overhead press held after a miss")
        #expect(press.detail == "Same weight, aim for 6 · 40 kg × 5, 5, 4")
    }

    @Test("loads read as the gym loads them, in kilograms and in pounds")
    func plateRounding() throws {
        // The estimate says 63.75 kg; the plates make 62.5.
        let kg = session(on: monday, [sets("barbell-row", 60, [11, 11, 11], target: 8, [.green], on: monday)])
        #expect(taught(kg).lessons.first?.detail == "All three sets felt easy · 60 → 62.5 kg")
        // 135 lb is 61.23 kg; the next step, 140 lb, reads back as 140, not 139.99.
        let lb = session(
            on: monday,
            [
                sets("barbell-row", WeightUnit.lb.toKilograms(135), [11, 11, 11], target: 8, [.green], on: monday),
                sets("db-curl", WeightUnit.lb.toKilograms(25), [12, 12, 12], target: 10, [.green], on: monday, at: 30),
            ])
        let (lessons, next) = taught(lb, unit: .lb)
        let row = try #require(lesson(lessons, "barbell-row"))
        #expect(row.title == "Row moves up 5 lb next time")
        #expect(row.detail == "All three sets felt easy · 135 → 140 lb")
        #expect(abs((next["barbell-row"]?.workSets.first?.loadKg ?? 0) - WeightUnit.lb.toKilograms(140)) < 0.001)
        let curl = try #require(lesson(lessons, "db-curl"))
        #expect(curl.title == "Dumbbell Curl moves up 5 lb next time")
        #expect(curl.detail == "12 reps, the top of the range · 25 → 30 lb each")
    }

    @Test("bodyweight and timed work have no load to move, until the planner adds some")
    func bodyweightAndTimed() throws {
        let record = session(
            on: monday,
            [
                sets("push-up", 0, [12, 11, 10], target: 12, [.orange], on: monday),
                sets("plank", 0, [1, 1, 1], target: 1, [nil], on: monday, at: 10),
            ])
        let (lessons, next) = taught(record)
        #expect(next["push-up"]?.workSets.first?.loadKg == 0)
        #expect(next["plank"] != nil)
        #expect(lessons.allSatisfy { $0.exerciseID == nil }, "\(lessons.map(\.title))")
        // Fifteen easy push-ups top the range: next time adds the smallest plate, and says so.
        let top = session(on: monday, [sets("push-up", 0, [15, 15, 15], target: 12, [.green], on: monday)])
        let push = try #require(lesson(taught(top).lessons, "push-up"))
        #expect(push.title == "Push-Up moves up 1.25 kg next time")
        #expect(push.detail == "15 reps, the top of the range · Bodyweight → +1.25 kg")
    }

    @Test("next time in the deload says nothing about the load, and a miss keeps its old line")
    func deloadNext() throws {
        // The last loading week's Monday: day A comes round again in the deload.
        let last = Fixture.start.adding(weeks: 4)
        let record = session(
            on: last,
            [
                sets("barbell-row", 70, [11, 11, 11], target: 8, [.green], on: last),
                sets("barbell-back-squat", 100, [4, 4, 4], target: 6, [.red], on: last, at: 20),
            ])
        let (lessons, next) = taught(record)
        #expect(next["barbell-row"]?.mode == .deload)
        #expect(lessons.map(\.title) == ["Squat: a missed set"])
        #expect(lessons.first?.detail == "That's data; next time adjusts")
        // And a deload's own sets never set the next session's weights.
        var deload = session(on: monday, [sets("barbell-row", 52.5, [8, 8], target: 8, [.green], on: monday)])
        deload.deload = true
        #expect(taught(deload).lessons.allSatisfy { $0.exerciseID == nil })
    }

    @Test("the card keeps four, most important first")
    func rankedAndCapped() throws {
        let record = session(
            on: monday,
            [
                sets("db-curl", 12, [12, 12, 12], target: 10, [.green], on: monday),
                sets("barbell-overhead-press", 40, [6, 6, 6], target: 6, [.orange], on: monday, at: 10),
                sets("barbell-row", 60, [11, 11, 11], target: 8, [.green], on: monday, at: 20),
                sets("barbell-back-squat", 100, [4, 4, 4], target: 6, [.red], on: monday, at: 30),
            ])
        let rest = RestReview(rests: (0..<6).map { _ in RestReview.Entry(planned: 90, taken: 50, recoveredEarly: true, setOnTarget: true) })
        let (lessons, _) = taught(record, rest: rest)
        #expect(lessons.count == SessionLessons.limit)
        #expect(lessons.map(\.kind) == [.missed, .up, .held, .rest])
        #expect(lessons.map(\.exerciseID) == ["barbell-back-squat", "barbell-row", "barbell-overhead-press", nil])
        #expect(lessons.map(\.tone) == [.bad, .good, .ok, .accent])
    }

    // MARK: Rests

    /// Curls with 90 s of rest that heart rate may end after 45: the first set, then one after each
    /// of `rests` seconds (a rest under 90 ended then), logged as it ends, on target but for the sets
    /// after the rests `missing`, with readings through the rests when there's a heart rate.
    func curls(rests: [Int], heartRate: Bool, missing: Set<Int> = []) -> LiveSession {
        let start = Fixture.start.date().addingTimeInterval(18 * 3600)
        let item = PlannedItem(
            slotID: UUID(), block: .accessory, exerciseID: "db-curl", role: .accessory,
            sets: (0...rests.count).map { _ in SetPrescription(kind: .working, loadKg: 12, targetReps: 10, targetRIR: 2) },
            repRange: RepRange(8, 12), rest: RestPlan(target: 90, minimum: 45, heartRateGuided: true))
        var live = LiveSession(
            plan: SessionPlan(
                day: Fixture.start, title: "Upper A", mesocycleID: nil, dayID: nil, week: 0, deload: false, checkIn: false, assessment: false,
                minimumEffectiveDose: false, items: [item], notes: [], quests: []),
            device: "Test", now: start)
        let environment = SessionEnvironment(
            catalog: Fixture.catalog, gym: Gym.preset(.fullGym, unit: .kg), trust: TrustState(experience: .intermediate),
            phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: [:], enduranceScore: 50, heartRateGuidedRest: true)
        let zones = HeartRateZones(resting: 60, maximum: 190)
        var clock = start
        live.log(item: 0, set: 0, reps: 10, loadKg: 12, rating: .orange, environment: environment, now: clock)
        for (index, rest) in rests.enumerated() {
            if heartRate {
                // 150 at the end of the set, ten down a reading to 100: recovered (131) by the minimum.
                for second in stride(from: 5, through: rest, by: 5) {
                    live.record(heartRate: max(100, 150 - Double(second / 5) * 10), zones: zones, now: clock.addingTimeInterval(Double(second)))
                }
            }
            clock = clock.addingTimeInterval(Double(rest))
            if rest < 90 { live.endRest(now: clock) }
            // Logged as it ends, three seconds a rep later.
            let target = live.items[0].sets[index + 1].prescription.targetReps
            let missed = missing.contains(index)
            let reps = missed ? target - 2 : target
            clock = clock.addingTimeInterval(Double(3 * reps))
            live.log(item: 0, set: index + 1, reps: reps, loadKg: 12, rating: missed ? .red : .orange, environment: environment, now: clock)
        }
        return live
    }

    @Test("rests: heart rate ending them early, going before the timer, short rests that cost reps, running long, and nothing to say")
    func rests() throws {
        let zones = HeartRateZones(resting: 60, maximum: 190)
        // Ended at 50 s by a recovered heart rate, every set after on target.
        let guided = RestReview(session: curls(rests: [50, 50, 50], heartRate: true), zones: zones)
        #expect(guided.rests.map(\.taken) == [50, 50, 50])
        #expect(guided.rests.allSatisfy { $0.recoveredEarly == true && $0.setOnTarget })
        #expect(guided.lesson?.title == "Rest ran short and you were ready")
        #expect(guided.lesson?.detail == "Heart rate recovered early on 3 of 3 rests")
        #expect(guided.lesson?.tone == .accent)

        // The same without a Watch: nothing says heart rate, only that the sets held up.
        let skipped = RestReview(session: curls(rests: [50, 60, 90], heartRate: false), zones: zones)
        #expect(skipped.rests.allSatisfy { $0.recoveredEarly == nil })
        #expect(skipped.lesson?.detail == "You went before the timer on 2 of 3 rests, reps on target")

        // Short, and then short of the reps; or short of them after two of five, which the other three
        // outweigh.
        let cost = RestReview(session: curls(rests: [40, 40, 40], heartRate: false, missing: [0, 1, 2]), zones: zones)
        #expect(cost.lesson?.title == "Short rests cost reps")
        #expect(cost.lesson?.detail == "3 of the 3 sets after a short rest fell short")
        let mostly = RestReview(session: curls(rests: [50, 50, 50, 50, 50], heartRate: true, missing: [1, 3]), zones: zones)
        #expect(mostly.lesson?.title == "Rest ran short and you were ready")
        #expect(mostly.lesson?.detail == "Heart rate recovered early on 3 of 5 rests")

        // Two and a half minutes for a minute and a half, twice of three.
        let long = RestReview(session: curls(rests: [160, 150, 90], heartRate: false), zones: zones)
        #expect(long.lesson?.title == "Rest ran long")
        #expect(long.lesson?.detail == "Over the timer by 1:05 on average, on 2 of 3 rests")

        // Rests as planned, a single short one, or no rests at all: nothing to say.
        #expect(RestReview(session: curls(rests: [90, 95, 90], heartRate: true), zones: zones).lesson == nil)
        #expect(RestReview(session: curls(rests: [50, 90, 90], heartRate: false), zones: zones).lesson == nil)
        #expect(RestReview(session: curls(rests: [], heartRate: false), zones: zones).rests.isEmpty)
    }

    // MARK: A lifter over weeks

    @Test("over a block, what the summary says of next time is what the next session with the lift asks")
    func promisesKept() throws {
        let profile = Fixture.profile(days: 4)
        let settings = LiftSettings(selfReportedPhase: .maintaining)
        let gym = Gym.preset(.fullGym, unit: .kg)
        let block = ProgramGenerator.generate(Fixture.input(profile, kind: .standard))
        var performer = Performer(
            e1rm: [
                "barbell-back-squat": 140, "conventional-deadlift": 165, "barbell-bench-press": 95, "barbell-overhead-press": 55,
                "barbell-row": 85, "barbell-incline-bench-press": 78,
            ],
            defaultE1RM: 60)
        var sessions: [SessionRecord] = []
        var promised: [String: (load: Double, made: Day, trust: TrustState)] = [:]
        var kept = 0
        var learned = 0
        var kinds: [SessionLesson.Kind: Int] = [:]
        let days = (0..<(7 * 5)).map { Fixture.start.adding(days: $0) }.filter { profile.schedule.trainingDays.contains($0.weekday) }
        for (index, date) in days.enumerated() {
            let state = LiftState(
                profile: profile, settings: settings, gym: gym, catalog: Fixture.catalog, sessions: sessions, mesocycles: [block],
                bodyweightKg: 80, today: date)
            let analysis = Analyst.analyse(state)
            let next = try #require(analysis.next)
            var context = PlanningContext(
                catalog: Fixture.catalog, gym: gym, profile: profile, settings: settings, trust: analysis.trust, phase: analysis.phase,
                life: analysis.life, history: analysis.history, bodyweightKg: 80, enduranceScore: analysis.endurance.score,
                sessionIndexInWeek: next.doneThisWeek)
            context.heat = analysis.heat
            let plan = SessionPlanner.plan(next.day, of: next.mesocycle, on: date, context: context)
            // Each promise is kept by the next session with the lift, but for what the sessions in
            // between taught about the ratings (trust): planned with the trust the promise was made
            // with, it's exactly what was promised.
            for item in plan.items where item.isStrength {
                guard let promise = promised.removeValue(forKey: item.exerciseID) else { continue }
                if item.workSets.first?.loadKg == promise.load {
                    kept += 1
                    continue
                }
                learned += 1
                var then = context
                then.trust = promise.trust
                let again = SessionPlanner.plan(next.day, of: next.mesocycle, on: date, context: then).items
                    .first { $0.exerciseID == item.exerciseID }
                #expect(
                    again?.workSets.first?.loadKg == promise.load,
                    "\(item.exerciseID) on \(date): promised \(promise.load) on \(promise.made), asked \(item.workSets.first?.loadKg ?? -1)")
            }
            // Every fourth session an off day, 8% down, so sets fall short.
            let off = index % 4 == 3
            if off { for key in performer.e1rm.keys { performer.e1rm[key, default: 0] *= 0.92 } }
            var live = LiveSession(plan: plan, device: "Test", now: date.date().addingTimeInterval(18 * 3600))
            let environment = SessionEnvironment(
                catalog: Fixture.catalog, gym: gym, trust: analysis.trust, phase: analysis.phase.effects, bodyweightKg: 80,
                history: analysis.history, enduranceScore: nil, heartRateGuidedRest: false)
            performer.train(&live, environment: environment, at: date.date().addingTimeInterval(18 * 3600))
            if off { for key in performer.e1rm.keys { performer.e1rm[key, default: 0] /= 0.92 } }
            let record = live.record(feedback: nil, now: date.date().addingTimeInterval(19 * 3600))
            sessions.append(record)

            let after = LiftState(
                profile: profile, settings: settings, gym: gym, catalog: Fixture.catalog, sessions: sessions, mesocycles: [block],
                bodyweightKg: 80, today: date)
            let analysed = Analyst.analyse(after)
            let items = NextTime.items(after: record, state: after, analysis: analysed)
            let lessons = SessionLessons.lessons(
                record: record, plan: plan, next: items, rest: RestReview(session: live, zones: HeartRateZones(resting: 60, maximum: 190)),
                catalog: Fixture.catalog, unit: .kg)
            #expect(lessons.count <= SessionLessons.limit)
            for lesson in lessons {
                kinds[lesson.kind, default: 0] += 1
                guard let id = lesson.exerciseID, [.up, .held, .down, .missed].contains(lesson.kind),
                    let load = items[id]?.workSets.first?.loadKg
                else { continue }
                let work = record.workSets.filter { $0.exerciseID == id }
                let top = work.map(\.loadKg).max() ?? 0
                let first = work.first?.loadKg ?? 0
                // The words agree with the numbers: against today's heaviest, or where today started
                // when the weight climbed during the session.
                switch lesson.kind {
                case .up where lesson.title.contains(" starts "): #expect(load > first && load < top, "\(lesson.title)")
                case .up: #expect(load > top && lesson.title.contains("moves up"), "\(lesson.title)")
                case .held where lesson.detail.hasPrefix("Starts at"): #expect(load == first && first < top, "\(lesson.title)")
                case .held: #expect(load == top && lesson.title.hasSuffix("held"), "\(lesson.title)")
                case .down: #expect(load < top && lesson.title.contains("comes down"), "\(lesson.title)")
                default: #expect(load <= top && work.contains { $0.rating == .red }, "\(lesson.title)")
                }
                promised[id] = (load, date, analysed.trust)
            }
            if ProcessInfo.processInfo.environment["PRINT_LESSONS"] != nil {
                print("\(date) \(record.title)")
                for lesson in lessons { print("  [\(lesson.tone)] \(lesson.title) / \(lesson.detail)") }
            }
        }
        #expect(kept >= 20 && learned * 5 <= kept, "promises kept: \(kept), moved by what later sessions taught: \(learned)")
        #expect((kinds[.up] ?? 0) > 0 && (kinds[.held] ?? 0) > 0 && (kinds[.missed] ?? 0) > 0, "\(kinds)")
    }
}
