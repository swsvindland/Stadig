import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// The scoreboard's clock: when each exercise still to come should start and when the session is
/// done, from what's left of it and the rest running.
@Suite("What's left of a session, timed")
struct SessionTimelineTests {
    let start = Fixture.start.date().addingTimeInterval(18 * 3600)

    func item(_ id: String, sets: Int = 3, load: Double, range: RepRange, rest: Int, group: Int? = nil) -> PlannedItem {
        PlannedItem(
            slotID: UUID(), block: .main, exerciseID: id, role: .main,
            sets: (0..<sets).map { _ in SetPrescription(kind: .working, loadKg: load, targetReps: range.middle, targetRIR: 2) },
            repRange: range, rest: RestPlan(target: rest, minimum: 0, heartRateGuided: false), supersetGroup: group)
    }

    func session(_ items: [PlannedItem]) -> LiveSession {
        LiveSession(
            plan: SessionPlan(
                day: Fixture.start, title: "Upper A", mesocycleID: nil, dayID: nil, week: 0, deload: false, checkIn: false,
                assessment: false, minimumEffectiveDose: false, items: items, notes: [], quests: []),
            device: "Test", now: start)
    }

    var environment: SessionEnvironment {
        SessionEnvironment(
            catalog: Fixture.catalog, gym: Gym.preset(.fullGym, unit: .kg), trust: TrustState(experience: .intermediate),
            phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: [:], enduranceScore: 50,
            heartRateGuidedRest: true)
    }

    @Test("each exercise starts after the sets and rests before it; done by leaves out the last rest")
    func beforeAnything() {
        // Bench: 45 s to set up, then 3 × (8 reps at 3 s + 15 s, and 120 s rest) = 522 s.
        // Fly: 45 s, then 3 × (13 reps at 3 s + 15 s, and 60 s rest) = 387 s, less the last rest.
        let live = session([
            item("barbell-bench-press", load: 60, range: RepRange(6, 10), rest: 120),
            item("cable-fly", load: 15, range: RepRange(10, 15), rest: 60),
        ])
        let timeline = live.timeline(now: start)
        #expect(timeline.starts[live.items[0].id] == start)
        #expect(timeline.starts[live.items[1].id] == start.addingTimeInterval(522))
        #expect(timeline.doneBy == start.addingTimeInterval(522 + 387 - 60))
        // Today's length for the same plan, which counts the last rest and rounds to the minute.
        #expect(live.plan.estimatedMinutes == Int((Double(522 + 387) / 60).rounded()))
    }

    @Test("during a rest the clock runs from its end; an exercise begun has no start, one done isn't counted")
    func midway() {
        var live = session([
            item("barbell-bench-press", load: 60, range: RepRange(6, 10), rest: 120),
            item("cable-fly", load: 15, range: RepRange(10, 15), rest: 60),
        ])
        live.log(item: 0, set: 0, reps: 8, loadKg: 60, rating: .orange, environment: environment, now: start.addingTimeInterval(100))
        let timeline = live.timeline(now: start.addingTimeInterval(130))
        #expect(timeline.starts[live.items[0].id] == nil)
        // The rest ends at 220; two bench sets of 159 s each come after it.
        #expect(timeline.starts[live.items[1].id] == start.addingTimeInterval(220 + 318))
        #expect(timeline.doneBy == start.addingTimeInterval(220 + 318 + 387 - 60))

        live.skip(item: 0, now: start.addingTimeInterval(140))
        live.endRest(now: start.addingTimeInterval(140))
        let skipped = live.timeline(now: start.addingTimeInterval(150))
        #expect(skipped.starts[live.items[1].id] == start.addingTimeInterval(150))
        #expect(skipped.doneBy == start.addingTimeInterval(150 + 387 - 60))
    }

    @Test("a superset's partner starts with the exercise it's paired with")
    func superset() {
        let live = session([
            item("db-curl", load: 12, range: RepRange(8, 12), rest: 60, group: 1),
            item("cable-fly", load: 15, range: RepRange(10, 15), rest: 60, group: 1),
        ])
        let timeline = live.timeline(now: start)
        #expect(timeline.starts[live.items[0].id] == start)
        #expect(timeline.starts[live.items[1].id] == start)
    }
}
