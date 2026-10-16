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
}
