import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// What a first session at the gym turned up: the warm-up's timing, a short hour, a busy gym,
/// a mistyped weight, a starting weight far from the real one, and the sauna.
@Suite("On the gym floor")
struct GymFloorTests {
    func context(_ profile: SharedProfile, gym: Gym? = nil) -> PlanningContext {
        PlanningContext(
            catalog: Fixture.catalog, gym: gym ?? Gym.preset(profile.equipment, unit: .kg), profile: profile,
            settings: LiftSettings(), trust: TrustState(experience: profile.experience), phase: .assumedMaintenance,
            life: LifeModeEffects(), history: [:], bodyweightKg: 84, enduranceScore: 50, sessionIndexInWeek: 0)
    }

    func environment(_ ctx: PlanningContext) -> SessionEnvironment {
        SessionEnvironment(
            catalog: Fixture.catalog, gym: ctx.gym, trust: ctx.trust, phase: ctx.phase.effects, bodyweightKg: 84,
            history: [:], enduranceScore: 50, heartRateGuidedRest: false)
    }

    @Test("the easy bike gets its five minutes, and the drills fit the rest")
    func warmup() throws {
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(days: 4, minutes: 60)))
        for day in m.days {
            let block = try #require(day.blocks.first { $0.kind == .warmup })
            let opener = try #require(block.slots.first)
            #expect(Fixture.catalog.resolve(opener.exerciseID).equipment.isCardio)
            #expect(opener.seconds == 300, "\(opener.seconds ?? 0) s")
            #expect(block.slots.count == 4)
            // What's in the block takes about the time it was given.
            let content = 300 + (block.slots.count - 1) * 60
            #expect(abs(content - block.minutes * 60) <= 60, "\(content) s in \(block.minutes) min")
        }
        #expect(Fixture.catalog.resolve("easy-bike-warmup").name == "Easy Bike")
    }

    @Test("no lift gets a single set, and spare time goes to more sets before more cardio")
    func fillsTheHour() {
        for minutes in [45, 60, 75, 90] {
            for days in [3, 4] {
                let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(days: days, minutes: minutes), kind: .assessment))
                for day in m.days {
                    #expect(day.strengthSlots.allSatisfy { $0.sets(week: 0) >= 2 }, "\(minutes) min \(day.name)")
                    #expect(day.minutes <= minutes, "\(day.name) is \(day.minutes) of \(minutes) min")
                }
            }
        }
        // An hour and a half is more lifting than an hour, not just a longer StairMaster.
        func workSets(_ minutes: Int) -> Int {
            ProgramGenerator.generate(Fixture.input(Fixture.profile(days: 4, minutes: minutes))).days
                .flatMap(\.strengthSlots).map { $0.sets(week: 0) }.reduce(0, +)
        }
        #expect(workSets(90) > workSets(60))
    }

    @Test("an exercise can be done now, ahead of the plan, with its superset partner")
    func doNext() throws {
        let profile = Fixture.profile()
        let m = ProgramGenerator.generate(Fixture.input(profile))
        var live = LiveSession(plan: SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: context(profile)), device: "Test")
        let last = try #require(live.items.lastIndex { $0.plan.isStrength })
        let id = live.items[last].id
        live.doNext(item: last)
        #expect(live.items.first?.id == id)
        #expect(live.current?.item == 0)
        #expect(live.items.count == live.plan.items.count)

        let short = Fixture.profile(days: 3, minutes: 30)
        let sm = ProgramGenerator.generate(Fixture.input(short))
        var superset = LiveSession(plan: SessionPlanner.plan(sm.days[0], of: sm, on: Fixture.start, context: context(short)), device: "Test")
        let group = try #require(superset.items.lastIndex { $0.plan.supersetGroup != nil })
        let partners = superset.items.filter { $0.plan.supersetGroup == superset.items[group].plan.supersetGroup }.map(\.id)
        let other = try #require(superset.items.indices.last { superset.items[$0].plan.supersetGroup == nil && superset.items[$0].plan.isStrength })
        superset.doNext(item: other)
        superset.doNext(item: group)
        #expect(Set(superset.items.prefix(partners.count).map(\.id)) == Set(partners), "the pair stays together")
    }

    @Test("a mistyped weight can be corrected, and the next sets follow the correction")
    func editSet() throws {
        let profile = Fixture.profile()
        let m = ProgramGenerator.generate(Fixture.input(profile, kind: .assessment))
        let ctx = context(profile)
        var live = LiveSession(plan: SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: ctx), device: "Test")
        let env = environment(ctx)
        let finding = { (item: LiveItem) in item.sets.filter { $0.prescription.kind == .findingWeight }.count >= 2 }
        let index = try #require(live.items.firstIndex { $0.plan.isStrength && finding($0) })
        // After any warm-ups toward a guess at the weight.
        let first = try #require(live.items[index].sets.firstIndex { $0.prescription.kind == .findingWeight })
        // 30 kg typed instead of 100, rated easy: the next set builds on 30.
        live.log(item: index, set: first, reps: 10, loadKg: 30, rating: .green, environment: env)
        let fromTypo = try #require(live.items[index].sets[first + 1].prescription.loadKg)
        #expect(fromTypo < 50)
        live.edit(item: index, set: first, reps: 10, loadKg: 100, rating: .green, environment: env)
        #expect(live.items[index].sets[first].logged?.loadKg == 100)
        let corrected = try #require(live.items[index].sets[first + 1].prescription.loadKg)
        #expect(corrected >= 100, "\(corrected)")
        // A rating tapped too fast: red to orange holds the weight instead of dropping it.
        live.edit(item: index, set: first, reps: 10, loadKg: 100, rating: .orange, environment: env)
        #expect(live.items[index].sets[first + 1].prescription.loadKg == 100)
    }

    @Test("starting weights land near what people lift, not an empty bar")
    func startingLoads() throws {
        func estimate(_ id: String, reps: Int = 10, sex: BiologicalSex = .male, experience: TrainingExperience = .intermediate) -> Double? {
            StartingLoad.estimate(Fixture.catalog.resolve(id), reps: reps, bodyweightKg: 84, sex: sex, experience: experience)
        }
        let legPress = try #require(estimate("leg-press"))
        #expect((90...170).contains(legPress), "\(legPress) kg")
        let dbBench = try #require(estimate("db-bench-press"))
        #expect((15...35).contains(dbBench), "\(dbBench) kg a hand")
        let pulldown = try #require(estimate("lat-pulldown"))
        #expect((35...70).contains(pulldown), "\(pulldown) kg")
        let squat = try #require(estimate("barbell-back-squat", reps: 5))
        #expect((60...130).contains(squat), "\(squat) kg")
        #expect(try #require(estimate("leg-press", experience: .novice)) < legPress)
        #expect(try #require(estimate("leg-press", sex: .female)) < legPress)
        #expect(try #require(estimate("leg-press", reps: 15)) < legPress)
        #expect(estimate("push-up") == nil)
    }

    @Test("a sauna is offered after training where the gym has one, outside the session's time")
    func sauna() throws {
        let profile = Fixture.profile()
        let m = ProgramGenerator.generate(Fixture.input(profile))
        let plain = SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: context(profile))
        #expect(!plain.items.contains { $0.block == .recovery }, "a full gym doesn't assume one")
        var gym = Gym.preset(.fullGym, unit: .kg)
        gym.apparatus.insert(.sauna)
        let plan = SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: context(profile, gym: gym))
        let last = try #require(plan.items.last)
        #expect(last.block == .recovery && last.exerciseID == "sauna" && last.seconds == 600, "a first time is ten minutes")
        #expect(plan.estimatedMinutes == plain.estimatedMinutes)
        gym.apparatus = gym.apparatus.subtracting([.sauna]).union([.steamRoom])
        let steam = SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: context(profile, gym: gym))
        #expect(steam.items.last?.exerciseID == "steam-room")
    }

    @Test("minutes in each heart-rate zone come from the readings")
    func zones() {
        let profile = Fixture.profile()
        let m = ProgramGenerator.generate(Fixture.input(profile))
        let start = Fixture.start.date()
        var live = LiveSession(plan: SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: context(profile)), device: "Test", now: start)
        let zones = HeartRateZones(resting: 60, maximum: 190)
        for second in stride(from: 0, to: 600, by: 5) {
            live.record(heartRate: second < 300 ? 145 : 165, zones: zones, now: start.addingTimeInterval(TimeInterval(second)))
        }
        let minutes = live.zoneMinutes(from: start, to: start.addingTimeInterval(600), zones: zones)
        #expect(abs((minutes[2] ?? 0) - 5) < 0.2 && abs((minutes[4] ?? 0) - 5) < 0.2, "\(minutes)")
        #expect(live.averageHeartRate(from: start, to: start.addingTimeInterval(600)) == 155)
    }

    @Test("a hotter room means fewer minutes for the same heat, and 10 at 190 °F is more than 20 at 175 °F")
    func heatDose() {
        func c(_ f: Double) -> Double { (f - 32) * 5 / 9 }
        #expect(HeatDose.dose(minutes: 10, temperatureC: c(190), room: "sauna") > HeatDose.dose(minutes: 20, temperatureC: c(175), room: "sauna"))
        let last = HeatLog(exerciseID: "sauna", date: Date(), minutes: 20, temperatureC: c(175), rating: .orange)
        let plan = HeatDose.plan([last], room: "sauna")
        #expect(plan.change == .same && plan.minutes(at: c(175), room: "sauna") == 20)
        let hot = plan.minutes(at: c(190), room: "sauna")
        #expect((6...10).contains(hot), "\(hot) min at 190 °F")
        #expect(plan.minutes(at: c(160), room: "sauna") == 25, "never past what's sensible, however cool")
        #expect(plan.minutes(at: 100, room: "sauna") <= 12)
        #expect(HeatDose.plan([], room: "sauna").minutes(at: 95, room: "sauna") == 5, "a first time in a very hot room is short")
    }

    @Test("how the last session felt moves the next, like a set's rating")
    func heatProgression() {
        let base = HeatLog(exerciseID: "sauna", date: Date(), minutes: 10, temperatureC: 80, rating: .orange)
        let dose = HeatDose.dose(minutes: 10, temperatureC: 80, room: "sauna")
        var easy = base
        easy.rating = .green
        var hard = base
        hard.rating = .red
        #expect(abs(HeatDose.plan([easy], room: "sauna").dose - dose * 1.15) < 0.01)
        #expect(abs(HeatDose.plan([hard], room: "sauna").dose - dose * 0.8) < 0.01)
        var earlier = base
        earlier.date = base.date.addingTimeInterval(-86_400 * 3)
        #expect(HeatDose.plan([earlier, base], room: "sauna").change == .more, "two just-rights in a row creep up")
        #expect(HeatDose.plan([base], room: "steam-room").change == .first, "rooms are counted apart")
        var long = base
        long.minutes = 25
        long.rating = .green
        #expect(HeatDose.plan([long], room: "sauna").dose == 25, "past twenty minutes' worth, easy holds rather than grows")
    }

    @Test("the sauna is kept apart from the lifting")
    func heatRecord() throws {
        let profile = Fixture.profile()
        let m = ProgramGenerator.generate(Fixture.input(profile))
        var gym = Gym.preset(.fullGym, unit: .kg)
        gym.apparatus.insert(.sauna)
        var live = LiveSession(plan: SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: context(profile, gym: gym)), device: "Test")
        let index = try #require(live.items.firstIndex { $0.plan.role == .recovery })
        live.logHeat(item: index, minutes: 12, temperatureC: 88, rating: .orange)
        #expect(live.items[index].isDone)
        let record = live.record(feedback: nil)
        #expect(record.heat?.first?.minutes == 12 && record.heat?.first?.temperatureC == 88)
        #expect(!record.exercises.contains { $0.exerciseID == "sauna" } && !record.mobility.contains("sauna"))
    }

    @Test("spare time never buys sets the recovery budget can't pay for, and a short day says why")
    func fatigueFirst() throws {
        let bjj = RecurringActivity(activity: .bjj, weekdays: [.monday, .tuesday, .thursday, .saturday], minutes: 90, intensity: 8)
        let busy = Fixture.profile(days: 4, minutes: 90, recurring: [bjj])
        let calm = Fixture.profile(days: 4, minutes: 90)
        func sets(_ profile: SharedProfile) -> Int {
            ProgramGenerator.generate(Fixture.input(profile)).days.flatMap(\.strengthSlots).map { $0.sets(week: 0) }.reduce(0, +)
        }
        #expect(sets(busy) < sets(calm), "four BJJ sessions a week leave less room for lifting")
        let m = ProgramGenerator.generate(Fixture.input(busy))
        #expect(m.days.flatMap(\.strengthSlots).allSatisfy { $0.sets(week: 0) >= 2 })
        let plan = SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: context(busy))
        if plan.estimatedMinutes <= 80 {
            #expect(plan.notes.contains { $0.contains("under your 90") && $0.contains("outside the gym") }, "\(plan.notes)")
        }
    }
}
