import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// A session the iPhone runs and the Watch logs into: the Watch's changes land once, in order and in
/// the right place, whatever order the copies and changes cross in, and both devices end up with the
/// same session.
@Suite("A session shared with the Watch")
struct SharedSessionTests {
    let start = Fixture.start.date()

    func session() -> (LiveSession, SessionEnvironment) {
        let profile = Fixture.profile()
        let m = ProgramGenerator.generate(Fixture.input(profile))
        let context = PlanningContext(
            catalog: Fixture.catalog, gym: Gym.preset(profile.equipment, unit: .kg), profile: profile, settings: LiftSettings(),
            trust: TrustState(experience: profile.experience), phase: .assumedMaintenance, life: LifeModeEffects(), history: [:],
            bodyweightKg: 80, enduranceScore: 50, sessionIndexInWeek: 0)
        let plan = SessionPlanner.plan(m.days[0], of: m, on: Fixture.start, context: context)
        let environment = SessionEnvironment(
            catalog: Fixture.catalog, gym: context.gym, trust: context.trust, phase: context.phase.effects, bodyweightKg: 80,
            history: [:], enduranceScore: 50, heartRateGuidedRest: true)
        return (LiveSession(plan: plan, device: "iPhone", now: start), environment)
    }

    /// What the Watch would log for the next set: the prescription, rated "just right".
    func nextSet(_ live: LiveSession) -> SessionChange.Kind? {
        guard let (item, set) = live.current else { return nil }
        let liveItem = live.items[item]
        let prescription = liveItem.sets[set].prescription
        if liveItem.plan.role == .conditioning {
            return .logConditioning(item: liveItem.id, minutes: 10, averageHeartRate: 140, zoneMinutes: [3: 10])
        }
        let rated = liveItem.plan.isStrength && prescription.kind != .warmup && prescription.kind != .repOut
        return .log(
            item: liveItem.id, set: set, reps: prescription.targetReps, loadKg: prescription.loadKg ?? 20, rating: rated ? .orange : nil,
            seconds: prescription.seconds, heartRatePeak: nil)
    }

    /// The phone takes everything the Watch sends, in the order it arrives.
    func deliver(_ changes: [SessionChange], to phone: inout LiveSession, _ environment: SessionEnvironment) {
        for change in changes { phone.take(change, environment: environment) }
    }

    @Test("a whole session logged on the Watch leaves the phone's session the same as the Watch's")
    func wholeSessionFromTheWatch() throws {
        var (phone, environment) = session()
        var watch = MirroredSession(phone, sentAt: start)
        var clock = start
        var steps = 0
        while let kind = nextSet(watch.session), steps < 200 {
            steps += 1
            clock = clock.addingTimeInterval(90)
            let made = watch.make(kind, environment: environment, now: clock)
            #expect(made?.sequence == steps)
            deliver(watch.pending, to: &phone, environment)
            // The phone's copy comes back after every change.
            let taken = watch.receive(phone.withoutHeartRate, sentAt: clock.addingTimeInterval(1), environment: environment)
            #expect(taken && watch.pending.isEmpty)
        }
        #expect(phone.isComplete && watch.session.isComplete)
        #expect(phone == watch.session)
        #expect(phone.takenChanges == steps)
    }

    @Test("a change that arrives twice (sent again, or by both routes) is taken once")
    func takenOnce() throws {
        var (phone, environment) = session()
        let index = try #require(phone.items.firstIndex { $0.plan.isStrength && $0.sets.filter { $0.prescription.kind != .warmup }.count > 1 })
        let first = try #require(phone.items[index].sets.firstIndex { $0.prescription.kind != .warmup })
        let load = phone.items[index].sets[first].prescription.loadKg ?? 40
        let change = SessionChange(
            .log(item: phone.items[index].id, set: first, reps: 8, loadKg: load, rating: .green, seconds: nil, heartRatePeak: nil),
            session: phone.id, sequence: 1, date: start)
        let taken = phone.take(change, environment: environment)
        let once = phone
        let again = phone.take(change, environment: environment)
        #expect(taken && !again)
        #expect(phone == once)
    }

    @Test("a set logged on a set just added, arriving before the add, waits for it rather than being lost")
    func outOfOrder() throws {
        var (phone, environment) = session()
        var watch = MirroredSession(phone, sentAt: start)
        let item = try #require(phone.items.first { $0.plan.isStrength && $0.takesMoreSets })
        let madeAdd = watch.make(.addSet(item: item.id), environment: environment, now: start)
        let madeLog = watch.make(
            .log(item: item.id, set: item.sets.count, reps: 9, loadKg: 50, rating: .orange, seconds: nil, heartRatePeak: nil),
            environment: environment, now: start.addingTimeInterval(60))
        let added = try #require(madeAdd)
        let log = try #require(madeLog)
        // The log alone gets there first: it waits.
        let early = phone.take(log, environment: environment)
        #expect(!early && phone.takenChanges == 0)
        // Then everything pending, in order, as the Watch sends it.
        deliver([added, log], to: &phone, environment)
        let index = try #require(phone.item(item.id))
        #expect(phone.items[index].sets.count == item.sets.count + 1)
        #expect(phone.items[index].sets.last?.logged?.reps == 9)
    }

    @Test("sixty changes made out of reach land once each when the phone hears them, however often they're sent")
    func longDisconnect() throws {
        var (phone, environment) = session()
        var watch = MirroredSession(phone, sentAt: start)
        let item = try #require(phone.items.first { $0.plan.isStrength && $0.takesMoreSets })
        for minute in 0..<60 {
            _ = watch.make(.addSet(item: item.id), environment: environment, now: start.addingTimeInterval(Double(minute) * 60))
        }
        #expect(watch.pending.count == 60)
        // Sent every couple of seconds, by both routes, before a copy comes back.
        for _ in 0..<4 { deliver(watch.pending, to: &phone, environment) }
        let index = try #require(phone.item(item.id))
        #expect(phone.items[index].sets.count == item.sets.count + 60)
        let taken = watch.receive(phone.withoutHeartRate, sentAt: start.addingTimeInterval(3600), environment: environment)
        #expect(taken && watch.pending.isEmpty && watch.session == phone)
    }

    @Test("a change made to another session isn't taken")
    func anotherSessionsChange() throws {
        var (phone, environment) = session()
        let item = try #require(phone.items.first { $0.plan.isStrength })
        let stray = SessionChange(.skip(item: item.id), session: UUID(), sequence: 1, date: start)
        let taken = phone.take(stray, environment: environment)
        #expect(!taken && phone.takenChanges == 0 && !phone.items[0].skipped)
    }

    @Test("a set logged on the Watch lands on its exercise after Do This Now reordered the phone's list")
    func reorderedOnThePhone() throws {
        var (phone, environment) = session()
        var watch = MirroredSession(phone, sentAt: start)
        let strength = phone.items.indices.filter { phone.items[$0].plan.isStrength && phone.items[$0].plan.supersetGroup == nil }
        try #require(strength.count >= 2)
        let target = phone.items[strength[0]]
        let set = try #require(target.sets.firstIndex { $0.prescription.kind != .warmup })
        // The phone moves a later exercise ahead while the Watch logs the first.
        phone.doNext(item: strength[1], now: start)
        let made = watch.make(
            .log(item: target.id, set: set, reps: 6, loadKg: 60, rating: .orange, seconds: nil, heartRatePeak: nil),
            environment: environment, now: start.addingTimeInterval(5))
        let change = try #require(made)
        let taken = phone.take(change, environment: environment)
        #expect(taken)
        let moved = try #require(phone.item(target.id))
        #expect(moved != strength[0])
        #expect(phone.items[moved].sets[set].logged?.reps == 6)
        #expect(phone.items[moved].sets[set].logged?.exerciseID == target.exerciseID)
    }

    @Test("a set both devices logged is corrected, not adjusted for twice")
    func loggedOnBoth() throws {
        let (fresh, environment) = session()
        let index = try #require(fresh.items.firstIndex { $0.plan.isStrength && $0.sets.filter { $0.prescription.kind != .warmup }.count > 2 })
        let set = try #require(fresh.items[index].sets.firstIndex { $0.prescription.kind != .warmup })
        let load = fresh.items[index].sets[set].prescription.loadKg ?? 40
        var onlyOnce = fresh
        onlyOnce.log(item: index, set: set, reps: 8, loadKg: load, rating: .green, environment: environment, now: start)
        var both = fresh
        both.log(item: index, set: set, reps: 8, loadKg: load, rating: .green, environment: environment, now: start)
        both.apply(
            .log(item: fresh.items[index].id, set: set, reps: 8, loadKg: load, rating: .green, seconds: nil, heartRatePeak: nil),
            environment: environment, now: start.addingTimeInterval(2))
        #expect(both.items[index].sets.map(\.prescription) == onlyOnce.items[index].sets.map(\.prescription))
        #expect(both.items[index].loggedSets.count == 1)
    }

    @Test("a change naming an item that isn't there is taken, changing nothing, so the ones after it can be")
    func goneItem() throws {
        var (phone, environment) = session()
        let before = phone.items
        let gone = SessionChange(.skip(item: UUID()), session: phone.id, sequence: 1, date: start)
        let first = phone.take(gone, environment: environment)
        #expect(first && phone.items == before && phone.takenChanges == 1)
        let item = try #require(phone.items.first { $0.plan.isStrength })
        let next = SessionChange(.skip(item: item.id), session: phone.id, sequence: 2, date: start)
        let second = phone.take(next, environment: environment)
        let index = try #require(phone.item(item.id))
        #expect(second && phone.items[index].skipped)
    }

    @Test("a Watch that starts over (its app relaunched) numbers its changes on from what the phone has taken")
    func watchStartsOver() throws {
        var (phone, environment) = session()
        var first = MirroredSession(phone, sentAt: start)
        for _ in 0..<3 {
            let kind = try #require(nextSet(first.session))
            _ = first.make(kind, environment: environment, now: start)
        }
        deliver(first.pending, to: &phone, environment)
        // The Watch app is relaunched and joins again from the phone's copy.
        var again = MirroredSession(phone.withoutHeartRate, sentAt: start.addingTimeInterval(10))
        let kind = try #require(nextSet(again.session))
        let made = again.make(kind, environment: environment, now: start.addingTimeInterval(20))
        let change = try #require(made)
        #expect(change.sequence == 4)
        let taken = phone.take(change, environment: environment)
        #expect(taken)
    }

    @Test("a set logged on the Watch stays on screen until the phone's copy has it, and an old copy arriving late is dropped")
    func pendingStaysUntilTaken() throws {
        var (phone, environment) = session()
        var watch = MirroredSession(phone, sentAt: start)
        let before = phone.withoutHeartRate
        let kind = try #require(nextSet(phone))
        let made = watch.make(kind, environment: environment, now: start.addingTimeInterval(30))
        let change = try #require(made)
        let (item, set) = try #require(before.current)
        // A copy the phone sent before the change arrived: the set is still logged on the Watch.
        let older = watch.receive(before, sentAt: start.addingTimeInterval(10), environment: environment)
        #expect(older && watch.pending == [change])
        #expect(watch.session.items[item].sets[set].logged != nil)
        // The phone takes it, and its copy comes back.
        phone.take(change, environment: environment)
        let newer = watch.receive(phone.withoutHeartRate, sentAt: start.addingTimeInterval(40), environment: environment)
        #expect(newer && watch.pending.isEmpty)
        #expect(watch.session == phone)
        // The first copy turning up again, late, is ignored.
        let late = watch.receive(before, sentAt: start.addingTimeInterval(10), environment: environment)
        #expect(!late && watch.session.items[item].sets[set].logged != nil)
    }

    @Test("the Watch's heart rate stays when the phone's copy, which has none, arrives")
    func heartRateStays() throws {
        let (phone, environment) = session()
        var watch = MirroredSession(phone, sentAt: start)
        let zones = HeartRateZones.estimated(age: 35, resting: 60)
        watch.record(heartRate: 120, zones: zones, now: start.addingTimeInterval(5))
        watch.record(heartRate: 140, zones: zones, now: start.addingTimeInterval(10))
        var later = phone
        later.endRest(now: start.addingTimeInterval(12))
        let taken = watch.receive(later.withoutHeartRate, sentAt: start.addingTimeInterval(12), environment: environment)
        #expect(taken && watch.session.heartRateSamples.map(\.bpm) == [120, 140])
    }

    @Test("a copy of another session isn't taken as this one's")
    func anotherSession() {
        let (phone, environment) = session()
        var watch = MirroredSession(phone, sentAt: start)
        let (other, _) = session()
        let taken = watch.receive(other, sentAt: start.addingTimeInterval(5), environment: environment)
        #expect(!taken && watch.session.id == phone.id)
    }

    @Test("a swap, an added set and a skip made on the Watch come out the same on the phone")
    func swapAddAndSkip() throws {
        var (phone, environment) = session()
        var watch = MirroredSession(phone, sentAt: start)
        let strength = phone.items.filter(\.plan.isStrength)
        try #require(strength.count >= 3)
        let original = Fixture.catalog.resolve(strength[0].exerciseID)
        let alternative = try #require(Substitutions.candidates(for: original, in: Fixture.catalog.all, availability: nil).first)
        let kinds: [SessionChange.Kind] = [
            .swap(item: strength[0].id, to: alternative.id), .addSet(item: strength[1].id), .skip(item: strength[2].id),
            .skipSet(item: strength[1].id, set: strength[1].sets.count - 1),
        ]
        for (offset, kind) in kinds.enumerated() {
            _ = watch.make(kind, environment: environment, now: start.addingTimeInterval(Double(offset)))
        }
        deliver(watch.pending, to: &phone, environment)
        let taken = watch.receive(phone.withoutHeartRate, sentAt: start.addingTimeInterval(10), environment: environment)
        #expect(taken && watch.session == phone)
        #expect(phone.items[try #require(phone.item(strength[0].id))].exerciseID == alternative.id)
        #expect(phone.items[try #require(phone.item(strength[1].id))].sets.count == strength[1].sets.count + 1)
        #expect(phone.items[try #require(phone.item(strength[2].id))].skipped)
    }

    @Test("a session sent after every set stays small: compressed, without the heart rate")
    func messageSize() throws {
        var (live, environment) = session()
        let zones = HeartRateZones.estimated(age: 35, resting: 60)
        for second in 0..<3600 where second % 5 == 0 {
            live.record(heartRate: 120, zones: zones, now: start.addingTimeInterval(Double(second)))
        }
        var clock = start
        while let kind = nextSet(live) {
            clock = clock.addingTimeInterval(90)
            live.apply(kind, environment: environment, now: clock)
        }
        let message = MirrorMessage.session(live.withoutHeartRate, context: nil, sentAt: clock)
        let data = try #require(message.encoded())
        #expect(data.count < 16_000, "\(data.count) bytes")
        guard case .session(let back, _, let sentAt)? = MirrorMessage(encoded: data) else {
            Issue.record("didn't decode")
            return
        }
        #expect(back == live.withoutHeartRate && sentAt == clock)
    }

    @Test("a small message goes as plain JSON and reads back; noise, and an older build's discard, read as nothing")
    func plainMessages() throws {
        let join = try #require(MirrorMessage.join.encoded())
        #expect(String(decoding: join, as: UTF8.self).hasPrefix("{"))
        guard case .join? = MirrorMessage(encoded: join) else {
            Issue.record("didn't decode")
            return
        }
        #expect(MirrorMessage(encoded: Data("hello".utf8)) == nil)
        #expect(MirrorMessage(encoded: Data(#"{"discard":{}}"#.utf8)) == nil)
    }

    @Test("the session after next goes round the program's days")
    func followingDay() {
        let profile = Fixture.profile(days: 3)
        let m = ProgramGenerator.generate(Fixture.input(profile))
        let next = Analyst.nextSession(m, sessions: [], profile: profile, today: Fixture.start)
        #expect(next.followingDay.id == m.days[1].id)
        var last = next
        last.dayIndex = m.days.count - 1
        #expect(last.followingDay.id == m.days[0].id)
    }
}
