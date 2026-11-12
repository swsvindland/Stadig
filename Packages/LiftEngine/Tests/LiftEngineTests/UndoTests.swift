import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// Undo of the set just logged: the session goes back to exactly how it stood before the set, every
/// kind of set, after the rest has run or been changed; logging it again is logging it once; only
/// the last set, until another is logged; and only on the device that logged it, so the Watch and
/// the phone still end up with the same session.
@Suite("Undo the set just logged")
struct UndoTests {
    let start = Fixture.start.date().addingTimeInterval(18 * 3600)

    var environment: SessionEnvironment {
        SessionEnvironment(
            catalog: Fixture.catalog, gym: Gym.preset(.fullGym, unit: .kg), trust: TrustState(experience: .intermediate),
            phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: [:], enduranceScore: 50,
            heartRateGuidedRest: true)
    }

    func session(_ items: [PlannedItem]) -> LiveSession {
        LiveSession(
            plan: SessionPlan(
                day: Fixture.start, title: "Upper A", mesocycleID: nil, dayID: nil, week: 0, deload: false, checkIn: false,
                assessment: false, minimumEffectiveDose: false, items: items, notes: [], quests: []),
            device: "Test", now: start)
    }

    /// A bench press with two warm-ups, two work sets and a rep-out to finish, resting two minutes.
    func bench(_ kinds: [SetKind] = [.warmup, .warmup, .working, .working, .repOut], load: Double? = 60, group: Int? = nil) -> PlannedItem {
        PlannedItem(
            slotID: UUID(), block: group == nil ? .main : .accessory, exerciseID: group == nil ? "barbell-bench-press" : "db-curl",
            role: group == nil ? .main : .accessory,
            sets: kinds.map { kind in
                SetPrescription(
                    kind: kind, loadKg: kind == .warmup ? 20 : load, targetReps: kind == .warmup ? 5 : 8, targetRIR: kind == .repOut ? 0 : 2)
            },
            repRange: RepRange(6, 10), rest: RestPlan(target: 120, minimum: 0, heartRateGuided: false), supersetGroup: group)
    }

    func fly(group: Int) -> PlannedItem {
        PlannedItem(
            slotID: UUID(), block: .accessory, exerciseID: "cable-fly", role: .accessory,
            sets: (0..<3).map { _ in SetPrescription(kind: .working, loadKg: 15, targetReps: 12, targetRIR: 2) },
            repRange: RepRange(10, 15), rest: RestPlan(target: 60, minimum: 0, heartRateGuided: false), supersetGroup: group)
    }

    /// The parts of a session logging a set changes, the clock aside.
    func same(_ a: LiveSession, _ b: LiveSession, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.items == b.items, sourceLocation: sourceLocation)
        #expect(a.rest == b.rest, sourceLocation: sourceLocation)
        #expect(a.message == b.message, sourceLocation: sourceLocation)
        #expect(a.lastAdjustment == b.lastAdjustment, sourceLocation: sourceLocation)
        #expect(a.mobilityDone == b.mobilityDone, sourceLocation: sourceLocation)
    }

    /// The session with every logged set's record id the same: each log makes a new one.
    func ignoringRecordIDs(_ live: LiveSession) -> LiveSession {
        var copy = live
        let id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        for i in copy.items.indices {
            for s in copy.items[i].sets.indices { copy.items[i].sets[s].logged?.id = id }
        }
        return copy
    }

    /// Logs the set in front of you as the dock would: its prescription, with `rating` on a work set.
    @discardableResult
    func logCurrent(_ live: inout LiveSession, rating: SetRating? = .orange, reps: Int? = nil, load: Double? = nil, at seconds: Double)
        -> (item: Int, set: Int)?
    {
        guard let (item, set) = live.current else { return nil }
        let prescription = live.items[item].sets[set].prescription
        let rated = prescription.kind != .warmup && prescription.kind != .repOut
        live.log(
            item: item, set: set, reps: reps ?? prescription.targetReps, loadKg: load ?? prescription.loadKg, rating: rated ? rating : nil,
            environment: environment, now: start.addingTimeInterval(seconds))
        return (item, set)
    }

    @Test("a rated set's undo puts back its rest and the next sets' targets; logging it again is logging it once")
    func ratedSet() throws {
        var live = session([bench()])
        logCurrent(&live, at: 60)
        logCurrent(&live, at: 120)
        live.endRest(now: start.addingTimeInterval(200))
        let before = live
        // Easy at 62.5 for 9: the next set goes up, and the rest starts.
        let (item, set) = try #require(logCurrent(&live, rating: .green, reps: 9, load: 62.5, at: 300))
        let once = live
        #expect(once.items[item].sets[set + 1] != before.items[item].sets[set + 1], "the rating moved the next set")
        #expect(once.rest?.started == start.addingTimeInterval(300))
        let undoable = try #require(once.undoableSet)
        #expect(undoable.item == item && undoable.set == set && undoable.logged.reps == 9 && undoable.logged.loadKg == 62.5)

        var undone = once
        let undid = undone.undoLastSet(now: start.addingTimeInterval(310))
        #expect(undid)
        same(undone, before)
        #expect(undone.items[item].sets[set].isOpen)
        #expect(undone.current?.item == item && undone.current?.set == set)
        #expect(undone.undoableSet == nil && undone.updatedAt == start.addingTimeInterval(310))

        var again = undone
        logCurrent(&again, rating: .green, reps: 9, load: 62.5, at: 300)
        #expect(ignoringRecordIDs(again) == ignoringRecordIDs(once))
    }

    @Test("after the rest has run, been changed or cut short, undo still puts everything back")
    func afterTheRest() throws {
        // 225 lb squats, 4 × 8 in a 5–8 range: after a just-right set the reps fall, and fall
        // further for a rest cut short.
        var squat = bench([.working, .working, .working, .working], load: 102.5)
        squat.exerciseID = "barbell-back-squat"
        squat.repRange = RepRange(5, 8)
        squat.rest = RestPlan(target: 150, minimum: 150, heartRateGuided: false)
        var live = session([squat])
        logCurrent(&live, at: 60)
        live.endRest(now: start.addingTimeInterval(200))
        let before = live
        _ = try #require(logCurrent(&live, at: 300))
        let target = live.items[0].sets[2].prescription.targetReps
        live.extendRest(by: 15, now: start.addingTimeInterval(320))
        // Skipped 40 seconds in: the last set's reps come down for the shorter rest.
        live.endRest(now: start.addingTimeInterval(340))
        #expect(live.items[0].sets[2].prescription.targetReps < target)
        // Long after: the rest is over and the last set waits.
        let undid = live.undoLastSet(now: start.addingTimeInterval(900))
        #expect(undid)
        same(live, before)

        // And with the rest left to run its course.
        var ran = before
        logCurrent(&ran, at: 300)
        let rest = try #require(ran.rest)
        let undid2 = ran.undoLastSet(now: rest.endsAt.addingTimeInterval(60))
        #expect(undid2)
        same(ran, before)
    }

    @Test("a warm-up's undo takes back its short breather")
    func warmup() throws {
        var live = session([bench()])
        let before = live
        logCurrent(&live, at: 60)
        #expect(live.rest?.plan.target == 45)
        let undid = live.undoLastSet(now: start.addingTimeInterval(70))
        #expect(undid)
        same(live, before)
        #expect(live.rest == nil && live.current?.set == 0)
        var again = live
        logCurrent(&again, at: 60)
        var once = before
        logCurrent(&once, at: 60)
        #expect(ignoringRecordIDs(again) == ignoringRecordIDs(once))
    }

    @Test("a rep-out that ends the session comes back as the set to do, and the session isn't complete")
    func repOut() throws {
        var live = session([bench()])
        for second in [60.0, 120, 300, 500] { logCurrent(&live, at: second) }
        let before = live
        let (item, set) = try #require(logCurrent(&live, reps: 11, at: 700))
        #expect(live.items[item].sets[set].logged?.kind == .repOut && live.isComplete && live.rest == nil)
        let undid = live.undoLastSet(now: start.addingTimeInterval(710))
        #expect(undid)
        same(live, before)
        #expect(!live.isComplete && live.current?.set == set)
    }

    @Test("a superset partner's undo goes back to the partner, with the changeover before it")
    func supersetPartner() throws {
        var live = session([bench([.working, .working], load: 12, group: 1), fly(group: 1)])
        logCurrent(&live, at: 60)
        // The curl's set is logged: the fly is next, after the 20-second changeover.
        #expect(live.current?.item == 1 && live.rest?.plan.target == 20)
        let before = live
        let (item, _) = try #require(logCurrent(&live, at: 100))
        #expect(item == 1 && live.current?.item == 0)
        let undid = live.undoLastSet(now: start.addingTimeInterval(110))
        #expect(undid)
        same(live, before)
        #expect(live.current?.item == 1 && live.current?.set == 0)
    }

    @Test("a finding weight carried on and a drill counted done are taken back too")
    func findingWeightAndDrill() throws {
        var live = session([
            bench([.findingWeight, .findingWeight, .findingWeight], load: nil),
            PlannedItem(
                slotID: UUID(), block: .cooldown, exerciseID: "couch-stretch", role: .stretch,
                sets: [SetPrescription(kind: .working, loadKg: nil, targetReps: 1, targetRIR: 5, seconds: 60)],
                repRange: RepRange(1, 1), rest: RestPlan(target: 0, minimum: 0, heartRateGuided: false), seconds: 60),
        ])
        let before = live
        logCurrent(&live, load: 50, at: 60)
        #expect(live.items[0].sets[1].prescription.loadKg != nil)
        let undid = live.undoLastSet(now: start.addingTimeInterval(70))
        #expect(undid)
        same(live, before)
        #expect(live.items[0].sets.allSatisfy { $0.prescription.loadKg == nil })

        live.skip(item: 0, now: start.addingTimeInterval(80))
        let beforeDrill = live
        logCurrent(&live, at: 140)
        #expect(live.mobilityDone == ["couch-stretch"])
        let undid2 = live.undoLastSet(now: start.addingTimeInterval(150))
        #expect(undid2)
        same(live, beforeDrill)
        #expect(live.mobilityDone.isEmpty)
    }

    @Test("only the last set: once the next is logged, the one before stays")
    func onlyTheLast() throws {
        var live = session([bench([.working, .working, .working])])
        let first = try #require(logCurrent(&live, at: 60))
        let second = try #require(logCurrent(&live, at: 240))
        #expect(live.undoableSet?.set == second.set)
        let undid = live.undoLastSet(now: start.addingTimeInterval(250))
        #expect(undid)
        #expect(live.items[0].sets[second.set].isOpen)
        #expect(live.items[0].sets[first.set].logged != nil)
        #expect(live.undoableSet == nil)
        let after = live
        let undid2 = live.undoLastSet(now: start.addingTimeInterval(260))
        #expect(!undid2)
        #expect(live == after, "a second undo changes nothing")
    }

    @Test("a skip, swap, added set, correction or Do This Now leaves nothing to undo; the rest and a reorder don't")
    func whatEndsIt() throws {
        func logged() -> LiveSession {
            var live = session([bench([.working, .working, .working]), fly(group: 2)])
            logCurrent(&live, at: 60)
            return live
        }
        let changes: [(String, (inout LiveSession) -> Void)] = [
            ("skip a set", { $0.skipSet(item: 0, set: 2) }),
            ("skip the exercise", { $0.skip(item: 0) }),
            ("add a set", { $0.addSet(item: 0) }),
            ("correct a set", { $0.edit(item: 0, set: 0, reps: 7, loadKg: nil, rating: .red, environment: environment) }),
            ("do the fly now", { $0.doNext(item: 1) }),
            ("swap", { $0.swap(item: 0, to: Fixture.catalog.resolve("db-bench-press"), environment: environment) }),
        ]
        for (name, change) in changes {
            var live = logged()
            change(&live)
            #expect(live.undoableSet == nil, "\(name)")
            let undid = live.undoLastSet()
            #expect(!undid, "\(name)")
        }
        let kept: [(String, (inout LiveSession) -> Void)] = [
            ("15 s more", { $0.extendRest(by: 15) }),
            ("skip the rest", { $0.endRest() }),
            ("a heart-rate reading", { $0.record(heartRate: 120, zones: HeartRateZones(resting: 60, maximum: 190)) }),
            ("reorder", { $0.move(items: [1], to: 0) }),
        ]
        for (name, change) in kept {
            var live = logged()
            change(&live)
            #expect(live.undoableSet?.set == 0, "\(name)")
        }
    }

    @Test("kept across a relaunch, as the session in progress is")
    func survivesARelaunch() throws {
        var live = session([bench()])
        logCurrent(&live, at: 60)
        let data = try JSONEncoder().encode(live)
        var read = try JSONDecoder().decode(LiveSession.self, from: data)
        #expect(read == live)
        let undid = read.undoLastSet(now: start.addingTimeInterval(70))
        #expect(undid)
        #expect(read.items[0].sets[0].isOpen)
    }

    @Test("the phone can't undo the Watch's set; the phone's own undo reaches the Watch, and both end up the same")
    func withTheWatch() throws {
        var phone = session([bench([.working, .working, .working])])
        // Logged on the phone: the Watch's copy has no undo, the phone's does.
        logCurrent(&phone, at: 60)
        #expect(phone.withoutHeartRate.undo == nil && phone.undoableSet != nil)
        var watch = MirroredSession(phone.withoutHeartRate, sentAt: start.addingTimeInterval(61))
        let undid = phone.undoLastSet(now: start.addingTimeInterval(70))
        #expect(undid)
        let heard = watch.receive(phone.withoutHeartRate, sentAt: start.addingTimeInterval(71), environment: environment)
        #expect(heard)
        #expect(watch.session.items[0].sets[0].isOpen)
        #expect(watch.session == phone.withoutHeartRate)

        // Logged on the Watch, taken on the phone: nothing for the phone to undo.
        let item = phone.items[0].id
        let kind = SessionChange.Kind.log(item: item, set: 0, reps: 8, loadKg: 60, rating: .orange, seconds: nil, heartRatePeak: nil)
        _ = watch.make(kind, environment: environment, now: start.addingTimeInterval(100))
        for change in watch.pending { phone.take(change, environment: environment) }
        #expect(phone.items[0].sets[0].logged != nil)
        let nothing = phone.undoLastSet()
        #expect(phone.undoableSet == nil && !nothing)

        // The phone logs the next set and undoes it while the Watch, not yet told, logs that set too:
        // the Watch's set lands, and the two agree.
        logCurrent(&phone, at: 300)
        _ = watch.receive(phone.withoutHeartRate, sentAt: start.addingTimeInterval(301), environment: environment)
        var stale = MirroredSession(phone.withoutHeartRate, sentAt: start.addingTimeInterval(302))
        let undid2 = phone.undoLastSet(now: start.addingTimeInterval(310))
        #expect(undid2)
        _ = stale.make(
            .log(item: item, set: 1, reps: 7, loadKg: 60, rating: .orange, seconds: nil, heartRatePeak: nil), environment: environment,
            now: start.addingTimeInterval(315))
        for change in stale.pending { phone.take(change, environment: environment) }
        let caughtUp = stale.receive(phone.withoutHeartRate, sentAt: start.addingTimeInterval(320), environment: environment)
        #expect(caughtUp)
        #expect(stale.pending.isEmpty && stale.session == phone.withoutHeartRate)
        #expect(phone.items[0].sets[1].logged?.reps == 7)
    }
}
