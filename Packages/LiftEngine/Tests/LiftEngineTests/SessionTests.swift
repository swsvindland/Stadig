import Foundation
import Testing
import ExerciseLibrary
import SystemCore
@testable import LiftEngine

/// A lifter who performs exactly to a true strength, for driving whole sessions.
struct Performer {
    var e1rm: [String: Double] = [:]
    var defaultE1RM = 60.0
    var growthPerSession = 0.006

    func strength(of id: String) -> Double { e1rm[id] ?? defaultE1RM }

    mutating func train(_ session: inout LiveSession, environment: SessionEnvironment, at start: Date) {
        var clock = start
        var guardCount = 0
        while let (i, s) = session.current, guardCount < 400 {
            guardCount += 1
            clock = clock.addingTimeInterval(90)
            let item = session.items[i]
            let prescription = item.sets[s].prescription
            if item.plan.role == .conditioning {
                session.logConditioning(item: i, minutes: item.plan.conditioning?.minutes ?? 10, averageHeartRate: 130, zoneMinutes: [2: 10], now: clock)
                continue
            }
            if !item.plan.isStrength {
                session.log(item: i, set: s, reps: prescription.targetReps, loadKg: nil, rating: nil, seconds: prescription.seconds,
                            environment: environment, now: clock)
                continue
            }
            let exercise = environment.catalog.resolve(item.exerciseID)
            let truth = strength(of: exercise.id) * (1 - 0.02 * Double(item.loggedSets.filter { $0.kind.countsAsWork }.count))
            let bw = environment.bodyweightKg ?? 80
            let guess = OneRepMax.loggedLoad(forEffective: OneRepMax.load(e1rm: truth, reps: 10, rir: 4), basis: exercise.loadBasis, bodyweightKg: bw)
            let logged = prescription.loadKg ?? environment.increments(for: exercise).round(max(0, guess), down: true)
            let effective = OneRepMax.effectiveLoad(logged, basis: exercise.loadBasis, bodyweightKg: bw)
            let capacity = effective > 0 ? Int(OneRepMax.repsToFailure(e1rm: truth, at: effective)) : 20
            if prescription.kind == .warmup {
                session.log(item: i, set: s, reps: prescription.targetReps, loadKg: logged, rating: nil, environment: environment, now: clock)
            } else if prescription.kind == .repOut {
                session.log(item: i, set: s, reps: capacity, loadKg: logged, rating: nil, environment: environment, now: clock)
            } else if capacity < prescription.targetReps {
                session.log(item: i, set: s, reps: capacity, loadKg: logged, rating: .red, environment: environment, now: clock)
            } else {
                let reserve = capacity - prescription.targetReps
                session.log(item: i, set: s, reps: prescription.targetReps, loadKg: logged, rating: reserve >= 3 ? .green : .orange,
                            environment: environment, now: clock)
            }
        }
        for key in e1rm.keys { e1rm[key]! *= 1 + growthPerSession }
        defaultE1RM *= 1 + growthPerSession
    }
}

@Suite("Sessions")
struct SessionTests {
    func context(_ profile: SharedProfile, history: [String: [LoggedSet]] = [:], life: LifeModeEffects = LifeModeEffects(),
                 trust: TrustState? = nil) -> PlanningContext {
        PlanningContext(catalog: Fixture.catalog, gym: Gym.preset(profile.equipment, unit: .kg), profile: profile, settings: LiftSettings(),
                        trust: trust ?? TrustState(experience: profile.experience), phase: .assumedMaintenance, life: life, history: history,
                        bodyweightKg: 80, enduranceScore: 50, sessionIndexInWeek: 0)
    }

    @Test func firstSessionFindsWeights() {
        let profile = Fixture.profile(experience: .novice)
        let m = ProgramGenerator.generate(Fixture.input(profile, kind: .assessment))
        let plan = SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: context(profile))
        let strength = plan.items.filter(\.isStrength)
        #expect(!strength.isEmpty)
        #expect(strength.allSatisfy { $0.workSets.allSatisfy { $0.kind == .findingWeight && $0.loadKg == nil } })
        // Heavy lifts still warm up, toward a guess at the working weight.
        let squat = strength.first { Fixture.catalog.resolve($0.exerciseID).equipment == .barbell && $0.role == .main }
        #expect(squat.map { $0.sets.contains { $0.kind == .warmup && ($0.loadKg ?? 0) > 0 } } ?? true)
        #expect(plan.assessment)
        #expect(plan.notes.first?.contains("pick a weight") == true)
    }

    @Test func crunchModeIsTheMinimumEffectiveDose() {
        let profile = Fixture.profile()
        let m = ProgramGenerator.generate(Fixture.input(profile))
        let crunch = LifeModePeriod(kind: .crunch(CrunchDials(minutesAvailable: 20, equipment: .hotelGym)), start: Fixture.start,
                                    end: Fixture.start.adding(days: 7), createdBy: .liftTrack)
        let life = LifeModes.effects(on: Fixture.start, periods: [crunch])
        let plan = SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: context(profile, life: life))
        #expect(plan.minimumEffectiveDose)
        #expect(plan.items.allSatisfy { $0.block == .main })
        #expect(plan.items.allSatisfy { Fixture.catalog.resolve($0.exerciseID).equipment != .barbell })
        #expect(plan.items.allSatisfy { $0.workSets.count == 2 })
        #expect(plan.items.contains { $0.substitutedFor != nil })
    }

    @Test func injuredShoulderSwapsPressing() {
        let profile = Fixture.profile()
        let m = ProgramGenerator.generate(Fixture.input(profile))
        let injury = Injury(parts: [InjuredPart(.shoulder)], severity: .severe)
        let period = LifeModePeriod(kind: .injury(injury), start: Fixture.start, createdBy: .liftTrack)
        let life = LifeModes.effects(on: Fixture.start, periods: [period])
        let plan = SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: context(profile, life: life))
        for item in plan.items { #expect(!injury.excludes(Fixture.catalog.resolve(item.exerciseID))) }
    }

    @Test func liveSessionAdaptsAndRecords() {
        let profile = Fixture.profile(experience: .novice)
        let m = ProgramGenerator.generate(Fixture.input(profile, kind: .assessment))
        let ctx = context(profile)
        let plan = SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: ctx)
        var live = LiveSession(plan: plan, device: "Test", now: Fixture.start.date())
        let env = SessionEnvironment(catalog: Fixture.catalog, gym: ctx.gym, trust: ctx.trust, phase: ctx.phase.effects, bodyweightKg: 80,
                                     history: [:], enduranceScore: 50, heartRateGuidedRest: true)
        var performer = Performer()
        performer.train(&live, environment: env, at: Fixture.start.date())
        #expect(live.isComplete)
        let record = live.record(feedback: SessionFeedback(soreness: 1, energy: 4), now: Fixture.start.date().addingTimeInterval(3600))
        #expect(!record.exercises.isEmpty)
        #expect(record.workSets.allSatisfy { $0.loadKg > 0 || Fixture.catalog.resolve($0.exerciseID).loadBasis != .external })
        #expect(record.planned)
    }

    @Test func swapsReprescribeFromTheNewExercisesHistory() {
        let profile = Fixture.profile()
        let m = ProgramGenerator.generate(Fixture.input(profile))
        let ctx = context(profile)
        var live = LiveSession(plan: SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: ctx), device: "Test")
        let env = SessionEnvironment(catalog: Fixture.catalog, gym: ctx.gym, trust: ctx.trust, phase: ctx.phase.effects, bodyweightKg: 80,
                                     history: [:], enduranceScore: 50, heartRateGuidedRest: true)
        let index = live.items.firstIndex { $0.plan.isStrength }!
        let original = live.items[index].exerciseID
        let alternative = Substitutions.candidates(for: Fixture.catalog.resolve(original), in: Fixture.catalog.all, availability: nil).first!
        live.swap(item: index, to: alternative, environment: env)
        #expect(live.items[index].exerciseID == alternative.id)
        #expect(live.items[index].plan.substitutedFor == original)
    }

    @Test("a swap partway through an exercise keeps each exercise's sets its own")
    func swapAfterLoggedSets() throws {
        let profile = Fixture.profile()
        let m = ProgramGenerator.generate(Fixture.input(profile))
        let ctx = context(profile)
        let start = Fixture.start.date().addingTimeInterval(18 * 3600)
        var live = LiveSession(plan: SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: ctx), device: "Test", now: start)
        let index = try #require(live.items.firstIndex { $0.plan.role == .main && $0.plan.workSets.count >= 3 })
        let original = live.items[index].exerciseID
        let options = Substitutions.candidates(for: Fixture.catalog.resolve(original), in: Fixture.catalog.all, availability: nil)
        let replacement = try #require(options.first)
        // The replacement has a history of its own, far lighter than the lift it replaces.
        let lastWeek = Fixture.start.adding(days: -7).date().addingTimeInterval(18 * 3600)
        let history = [replacement.id: (0..<3).map {
            LoggedSet(exerciseID: replacement.id, date: lastWeek.addingTimeInterval(Double($0) * 180), loadKg: 30, reps: 10, rating: .orange,
                      bodyweightKg: 80)
        }]
        let env = SessionEnvironment(catalog: Fixture.catalog, gym: ctx.gym, trust: ctx.trust, phase: ctx.phase.effects, bodyweightKg: 80,
                                     history: history, enduranceScore: 50, heartRateGuidedRest: true)
        let work = live.items[index].sets.indices.filter { live.items[index].sets[$0].prescription.kind != .warmup }
        for (n, set) in work.prefix(2).enumerated() {
            live.log(item: index, set: set, reps: 8, loadKg: 100, rating: .orange, environment: env,
                     now: start.addingTimeInterval(Double(n + 1) * 180))
        }
        live.swap(item: index, to: replacement, environment: env, now: start.addingTimeInterval(540))
        let prescribed = live.items[index].sets.filter(\.isOpen).map(\.prescription)
        #expect(!prescribed.isEmpty && prescribed.allSatisfy { ($0.loadKg ?? 0) < 60 }, "\(prescribed)")

        // Correcting a set of the first lift leaves the replacement's sets as they were prescribed.
        let corrected = try #require(live.items[index].sets.firstIndex { $0.logged?.exerciseID == original })
        live.edit(item: index, set: corrected, reps: 8, loadKg: 102.5, rating: .green, environment: env)
        #expect(live.items[index].sets[corrected].logged?.loadKg == 102.5)
        #expect(live.items[index].sets.filter(\.isOpen).map(\.prescription) == prescribed)

        let open = try #require(live.items[index].nextSet)
        live.log(item: index, set: open, reps: 10, loadKg: 30, rating: .orange, environment: env, now: start.addingTimeInterval(720))
        let record = live.record(feedback: nil, now: start.addingTimeInterval(3600))
        let logs = record.exercises.filter { $0.slotID == live.items[index].plan.slotID }
        #expect(logs.map(\.exerciseID) == [original, replacement.id])
        #expect(logs.map(\.sets.count) == [2, 1])
        #expect(logs.allSatisfy { log in log.sets.allSatisfy { $0.exerciseID == log.exerciseID } })
        #expect(logs.map(\.substitutedFor) == [nil, original])

        // The analysis files every set under its own exercise, also in a session saved as one log.
        func analysedHistory(_ record: SessionRecord) -> [String: [LoggedSet]] {
            Analyst.analyse(LiftState(profile: profile, settings: LiftSettings(), gym: ctx.gym, catalog: Fixture.catalog, sessions: [record],
                                      bodyweightKg: 80, today: Fixture.start)).history
        }
        var saved = record
        saved.exercises = [ExerciseLog(slotID: logs[0].slotID, exerciseID: replacement.id, sets: logs.flatMap(\.sets), substitutedFor: original)]
        for analysed in [analysedHistory(record), analysedHistory(saved)] {
            #expect(analysed[original]?.count == 2)
            #expect(analysed[replacement.id]?.map(\.loadKg) == [30])
        }
        let exported = Export.tables(LiftState(profile: profile, settings: LiftSettings(), gym: ctx.gym, catalog: Fixture.catalog, sessions: [saved]))
        #expect(exported[1].rows.map { $0[3] } == [original, original, replacement.id])
    }

    @Test("a stand-in that must never go to failure never gets the planned lift's rep-out")
    func repOutsFollowTheStandIn() throws {
        let profile = Fixture.profile(experience: .novice)
        let availability = Gym.preset(.fullGym, unit: .kg).availability
        let all = Fixture.catalog.all
        // A safe-to-fail lift on the avoid list whose best stand-in mustn't be taken to failure.
        let pair = all.lazy.filter { $0.kind == .strength && $0.safetyTier == .safeToFail && !$0.timed && availability.allows($0) }
            .compactMap { planned -> (Exercise, Exercise)? in
                guard let standIn = Substitutions.candidates(for: planned, in: all, availability: availability, avoid: [planned.id]).first,
                      standIn.safetyTier == .neverToFailure, !standIn.timed else { return nil }
                return (planned, standIn)
            }.first
        let (planned, standIn) = try #require(pair)
        let slot = SlotPlan(exerciseID: planned.id, role: .main, sets: [3], repRange: RepRange(8, 12), restSeconds: 120)
        let day = PlannedDay(name: "Full body A", focus: .full, blocks: [SessionBlockPlan(kind: .main, minutes: 20, slots: [slot])])
        let m = Mesocycle(block: TrainingBlock(kind: .assessment, start: Fixture.start, loadingWeeks: 4, deloadWeeks: 0), split: .fullBody,
                          days: [day], priorities: [], rationale: Rationale(headline: ""), minutesPerSession: 60, phase: .assumedMaintenance)
        let lastWeek = Fixture.start.adding(weeks: 1).date().addingTimeInterval(18 * 3600)
        let history = Dictionary(uniqueKeysWithValues: [planned.id, standIn.id].map { id in
            (id, (0..<3).map { LoggedSet(exerciseID: id, date: lastWeek.addingTimeInterval(Double($0) * 180), loadKg: 40, reps: 10, rating: .orange,
                                         bodyweightKg: 80) })
        })
        func plan(avoid: Set<String>) throws -> PlannedItem {
            var ctx = context(profile, history: history)
            ctx.settings.avoid = avoid
            return try #require(SessionPlanner.plan(day, of: m, on: Fixture.start.adding(weeks: 2), context: ctx).items.first)
        }
        // As planned, the lift is the session's rep-out.
        #expect(try plan(avoid: []).sets.last?.kind == .repOut)
        let swapped = try plan(avoid: [planned.id])
        #expect(swapped.exerciseID == standIn.id)
        #expect(!swapped.sets.contains { $0.kind == .repOut }, "\(standIn.id) is never taken to failure")
    }

    @Test("crunch mode's stand-in gym is the same every time it's asked for")
    func crunchGymIsStable() {
        let profile = Fixture.profile()
        let crunch = LifeModePeriod(kind: .crunch(CrunchDials(minutesAvailable: 20, equipment: .hotelGym)), start: Fixture.start,
                                    end: Fixture.start.adding(days: 7), createdBy: .liftTrack)
        let ctx = context(profile, life: LifeModes.effects(on: Fixture.start, periods: [crunch]))
        #expect(ctx.todaysGym == ctx.todaysGym)
        #expect(ctx.todaysGym.access == .hotelGym && ctx.todaysGym.id != ctx.gym.id)
    }

    @Test("a session keeps the day it was done on after the phone travels")
    func sessionDayKeepsItsTimeZone() throws {
        // 23:30 on Sunday 18 October in Pago Pago (UTC-11) is already Monday nearly everywhere else.
        let pagoPago = try #require(TimeZone(identifier: "Pacific/Pago_Pago"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pagoPago
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 23, minute: 30)))
        let plan = SessionPlan(day: Fixture.start, title: "Upper A", mesocycleID: nil, dayID: nil, week: 0, deload: false, checkIn: false,
                               assessment: false, minimumEffectiveDose: false, items: [], notes: [], quests: [])
        let record = LiveSession(plan: plan, device: "Test", now: start)
            .record(feedback: nil, now: start.addingTimeInterval(3600), timeZone: pagoPago)
        #expect(record.timeZoneID == "Pacific/Pago_Pago")
        #expect(record.day == Day(year: 2026, month: 10, day: 18))

        // Saved before the zone was kept: read in the phone's zone, as before.
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        json.removeValue(forKey: "timeZoneID")
        let old = try JSONDecoder().decode(SessionRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.timeZoneID == nil)
        #expect(old.id == record.id && old.title == record.title)
        #expect(old.day == Day(old.start))
    }

    @Test("adding a set after a rep-out, extending and ending rest, and the heart-rate cap")
    func smallerMoves() throws {
        let profile = Fixture.profile()
        let m = ProgramGenerator.generate(Fixture.input(profile))
        let ctx = context(profile)
        let start = Fixture.start.date().addingTimeInterval(18 * 3600)
        var live = LiveSession(plan: SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: ctx), device: "Test", now: start)
        let env = SessionEnvironment(catalog: Fixture.catalog, gym: ctx.gym, trust: ctx.trust, phase: ctx.phase.effects, bodyweightKg: 80,
                                     history: [:], enduranceScore: 50, heartRateGuidedRest: false)
        let index = try #require(live.items.firstIndex { $0.plan.isStrength && $0.plan.supersetGroup == nil })
        let last = live.items[index].sets.count - 1
        live.items[index].sets[last].prescription.kind = .repOut
        live.log(item: index, set: last, reps: 12, loadKg: 60, rating: nil, environment: env, now: start.addingTimeInterval(60))
        // One more after a rep-out is an ordinary hard set at the weight just used.
        live.addSet(item: index, now: start.addingTimeInterval(70))
        let added = try #require(live.items[index].sets.last?.prescription)
        #expect(added.kind == .working && added.targetRIR == 1 && added.loadKg == 60)
        // Extending counts from when the rest would have ended; skipping the exercise ends it.
        let rest = try #require(live.rest)
        live.extendRest(by: 30, now: start.addingTimeInterval(80))
        #expect(live.rest?.endsAt == rest.endsAt.addingTimeInterval(30))
        live.skip(item: index, now: start.addingTimeInterval(90))
        #expect(live.rest == nil && live.items[index].isDone)
        // Moving an item later lands it before the one at the destination.
        let first = live.items[0].id
        live.moveItem(from: 0, to: 2)
        #expect(live.items[1].id == first)
        // A long session keeps the last 4,000 heart-rate readings.
        let zones = HeartRateZones(resting: 60, maximum: 190)
        for second in 0..<4_010 { live.record(heartRate: 120, zones: zones, now: start.addingTimeInterval(Double(second))) }
        #expect(live.heartRateSamples.count == 4_000)
        #expect(live.heartRateSamples.first?.date == start.addingTimeInterval(10))
    }
}

@Suite("A whole assessment")
struct JourneyTests {
    @Test func assessmentEndsInAPlanWithWhy() {
        let profile = Fixture.profile(days: 3, minutes: 60, experience: .novice)
        var settings = LiftSettings(assessmentStart: Fixture.start)
        settings.selfReportedPhase = .maintaining
        let gym = Gym.preset(.fullGym, unit: .kg)
        let assessment = ProgramGenerator.generate(Fixture.input(profile, kind: .assessment))
        var sessions: [SessionRecord] = []
        var performer = Performer(e1rm: ["barbell-back-squat": 120, "conventional-deadlift": 140, "barbell-bench-press": 60,
                                         "barbell-overhead-press": 38, "pull-up": 100, "barbell-row": 55, "barbell-incline-bench-press": 50],
                                  defaultE1RM: 60)
        for week in 0..<4 {
            for (i, day) in [0, 2, 4].enumerated() {
                let date = Fixture.start.adding(weeks: week).adding(days: day)
                var state = LiftState(profile: profile, settings: settings, gym: gym, catalog: Fixture.catalog, sessions: sessions,
                                      mesocycles: [assessment], bodyweightKg: 80, today: date)
                let analysis = Analyst.analyse(state)
                guard let next = analysis.next else { Issue.record("no next session"); return }
                let ctx = PlanningContext(catalog: Fixture.catalog, gym: gym, profile: profile, settings: settings, trust: analysis.trust,
                                          phase: analysis.phase, life: analysis.life, history: analysis.history, bodyweightKg: 80,
                                          enduranceScore: analysis.endurance.score, sessionIndexInWeek: i)
                let plan = SessionPlanner.plan(next.day, of: assessment, on: date, context: ctx)
                var live = LiveSession(plan: plan, device: "Test", now: date.date().addingTimeInterval(7 * 3600))
                let env = SessionEnvironment(catalog: Fixture.catalog, gym: gym, trust: analysis.trust, phase: analysis.phase.effects,
                                             bodyweightKg: 80, history: analysis.history, enduranceScore: nil, heartRateGuidedRest: false)
                performer.train(&live, environment: env, at: date.date().addingTimeInterval(7 * 3600))
                sessions.append(live.record(feedback: SessionFeedback(soreness: 1, energy: 3), now: date.date().addingTimeInterval(8 * 3600)))
                state.sessions = sessions
            }
        }
        let end = Fixture.start.adding(weeks: 4)
        let state = LiftState(profile: profile, settings: settings, gym: gym, catalog: Fixture.catalog, sessions: sessions,
                              mesocycles: [assessment], bodyweightKg: 80, today: end)
        let analysis = Analyst.analyse(state)
        let status = analysis.assessment!
        #expect(status.complete)
        #expect(status.workingWeightsFound == status.exercisesTotal, "\(status.workingWeightsFound)/\(status.exercisesTotal)")
        #expect(analysis.strength.categories.count >= 6, "\(analysis.strength.categories.map(\.category))")
        #expect(analysis.trust.score > TrainingExperience.novice.startingTrust)
        // Legs are far ahead of upper body for this lifter.
        #expect(analysis.strength.priorities.contains { $0.target == .region(.upperPush) && $0.emphasis > 0 })
        #expect((analysis.discipline.rate ?? 0) >= 0.9)

        let decision = Assessment.nextBlock(nutrition: nil, selfReported: settings.selfReportedPhase)
        #expect(decision.kind == .standard)
        var input = Fixture.input(profile, strength: analysis.strength)
        input.start = end
        input.previous = assessment
        input.trust = analysis.trust
        let block = ProgramGenerator.generate(input)
        #expect(block.rationale.headline.contains("comes first"))
        #expect(block.block.loadingWeeks == 5)
        let summary = Analyst.summary(state, analysis)
        #expect(summary.strength != nil)
        #expect(summary.sessions.count == 12)
        #expect(summary.stats.contains { $0.stat == .strength })
        if ProcessInfo.processInfo.environment["PRINT_PROGRAMS"] != nil {
            print(status.learned.joined(separator: "\n"))
            print(analysis.strength.categories.map { "\($0.category.label): \(Int($0.oneRepMaxKg)) kg → \(Int($0.score)) \($0.level)" }.joined(separator: "\n"))
            print("trust \(analysis.trust.score)")
            print(Fixture.describe(block))
        }
    }

    @Test func macroTrackStillDecidingMeansANeutralBlock() {
        let deciding = NutritionSummary(phase: nil, maintenanceKcal: nil, days: [])
        #expect(Assessment.nextBlock(nutrition: deciding, selfReported: .bulking).kind == .neutral)
        let decided = NutritionSummary(phase: NutritionPhase(kind: .cut, source: .macroTrack), maintenanceKcal: 2600, days: [])
        let decision = Assessment.nextBlock(nutrition: decided, selfReported: .bulking)
        #expect(decision.kind == .standard && decision.phase.kind == .cut)
        #expect(Assessment.nextBlock(nutrition: nil, selfReported: nil).askPhase)
    }

    @Test func exportsEveryTable() {
        let profile = Fixture.profile()
        let state = LiftState(profile: profile, settings: LiftSettings(), gym: Gym.preset(.fullGym, unit: .kg), catalog: Fixture.catalog,
                              sessions: [SessionRecord(start: Date(), end: Date(), title: "Upper A",
                                                       exercises: [ExerciseLog(exerciseID: "barbell-bench-press",
                                                                               sets: [LoggedSet(exerciseID: "barbell-bench-press", loadKg: 80, reps: 5, rating: .orange)])])])
        let tables = Export.tables(state)
        #expect(tables.map(\.name) == ["sessions", "sets", "outside-activities", "measurements", "tests"])
        #expect(tables[1].rows.first?[4] == "Barbell Bench Press")
        #expect(tables.allSatisfy { t in t.rows.allSatisfy { $0.count == t.header.count } })
    }
}

@Suite("Gym loads")
struct GymTests {
    @Test func platesAndSteps() {
        let gym = Gym.preset(.fullGym, unit: .kg)
        let bar = gym.increments(for: .barbell)
        #expect(bar.round(83, down: true) == 82.5)
        #expect(bar.step(100, direction: 1) == 102.5)
        #expect(bar.platesPerSide(100) == [25, 15])
        let lb = Gym.preset(.fullGym, unit: .lb).increments(for: .barbell)
        #expect(abs(WeightUnit.lb.fromKilograms(lb.round(WeightUnit.lb.toKilograms(225), down: true)) - 225) < 0.01)
        let db = Gym.preset(.hotelGym, unit: .kg).increments(for: .dumbbell)
        #expect(db.round(40, down: true) <= 22.5)
    }

    @Test("weighted pull-ups and dips start the crown at one zero, then the smallest plate")
    func beltLoadsStartAtOneZero() {
        let belt = Gym.preset(.fullGym, unit: .kg).increments(for: .bodyweight)
        let crown = belt.around(0)
        #expect(Array(crown.prefix(2)) == [0, 1.25])
        #expect(Set(crown).count == crown.count)
        #expect(belt.step(0, direction: 1) == 1.25)
        #expect(belt.step(1.25, direction: -1) == 0)
        // A bar goes from nothing to the empty bar.
        #expect(Array(Gym.preset(.fullGym, unit: .kg).increments(for: .barbell).around(0).prefix(2)) == [0, 20])
    }

    @Test("plates per side are the fewest for every load, in kg and lb")
    func platesPerSide() throws {
        // The exhaustive search over every cent the calculator used to run.
        func reference(_ bar: GymIncrements, _ kg: Double) -> [Double]? {
            let perSide = GymIncrements.cents((bar.gym.unit.fromKilograms(kg) - bar.base) / 2)
            guard perSide >= 0 else { return nil }
            let sizes = bar.gym.plates.map(GymIncrements.cents).sorted(by: >)
            var best: [Int: [Int]] = [0: []]
            if perSide > 0 {
                for total in 1...perSide {
                    var choice: [Int]?
                    for size in sizes {
                        if let rest = best[total - size], rest.count + 1 < choice?.count ?? .max { choice = [size] + rest }
                    }
                    if let choice { best[total] = choice }
                }
            }
            return best[perSide].map { $0.sorted(by: >).map { Double($0) / 100 } }
        }
        let kg = Gym.preset(.fullGym, unit: .kg).increments(for: .barbell)
        for load in stride(from: 20.0, through: 150, by: 1.25) { #expect(kg.platesPerSide(load) == reference(kg, load), "\(load) kg") }
        let lb = Gym.preset(.fullGym, unit: .lb).increments(for: .barbell)
        for load in stride(from: 45.0, through: 315, by: 5) {
            let kilograms = WeightUnit.lb.toKilograms(load)
            #expect(lb.platesPerSide(kilograms) == reference(lb, kilograms), "\(load) lb")
        }
        #expect(lb.platesPerSide(WeightUnit.lb.toKilograms(225)) == [45, 45])
        #expect(kg.platesPerSide(20) == [])
        #expect(kg.platesPerSide(15) == nil, "lighter than the bar")
        #expect(kg.platesPerSide(21) == nil, "half a kilo a side isn't makeable")
        #expect(Gym.preset(.fullGym, unit: .kg).increments(for: .dumbbell).platesPerSide(20) == nil)
    }
}
