import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import Testing

@testable import LiftTrack

/// Floor mode in the app: what the floor shows, and that its gestures log exactly what the dock's
/// buttons would, from the numbers the dock left.
@MainActor
@Suite("Floor mode")
struct FloorModeTests {
    /// A session moved on to its first main lift's first work set, past the warm-ups.
    private func atFirstWorkSet() throws -> AppModel {
        let model = TestApp().onboarded()
        model.start(try #require(model.plan()))
        let environment = try #require(model.environment)
        model.update { live in
            while let (i, s) = live.current, live.items[i].plan.block != .main || live.items[i].sets[s].prescription.kind == .warmup {
                if live.items[i].plan.block != .main {
                    live.skip(item: i)
                } else {
                    let set = live.items[i].sets[s].prescription
                    live.log(item: i, set: s, reps: set.targetReps, loadKg: set.loadKg, rating: nil, environment: environment)
                }
            }
            live.endRest()
        }
        return model
    }

    @Test("A weight and reps changed in the dock are what a tap on the floor logs, as Just right")
    func floorLogsTheDocksNumbers() throws {
        let model = try atFirstWorkSet()
        let (i, s) = try #require(model.live?.current)
        #expect(model.floorContent == .set(item: i, set: s, kind: .rated))

        let dock = SetDraft()
        dock.prepare(item: i, set: s, model: model)
        let prescribed = try #require(model.live?.items[i].sets[s].prescription)
        #expect(dock.reps == prescribed.targetReps)
        dock.load += 2.5
        dock.reps -= 1
        // Floor mode coming up asks for the same set again: what was changed is kept.
        dock.prepare(item: i, set: s, model: model)
        let changed = (load: dock.load, reps: dock.reps)

        dock.log(item: i, set: s, rating: .orange, model: model)
        let logged = try #require(model.live?.items[i].sets[s].logged)
        #expect(logged.loadKg == changed.load)
        #expect(logged.reps == changed.reps)
        #expect(logged.rating == .orange)
        // The rest that follows is what the floor shows next.
        #expect(model.floorContent == .rest)
    }

    @Test("Undo opens the set again with the numbers it was logged with, though the next set's were filled in")
    func undoKeepsTheNumbers() throws {
        let model = try atFirstWorkSet()
        let (i, s) = try #require(model.live?.current)
        let draft = SetDraft()
        draft.prepare(item: i, set: s, model: model)
        draft.load += 2.5
        draft.reps -= 1
        let changed = (load: draft.load, reps: draft.reps)
        let before = try #require(model.live)
        draft.log(item: i, set: s, rating: .green, model: model)
        let once = try #require(model.live)
        let rest = try #require(once.rest)
        #expect(model.justLogged(after: rest) == JustLogged(name: "Set 1", rating: .green, detail: "Easy", undoable: true))
        #expect(model.justLogged(after: rest)?.text == "Set 1 logged · Easy")
        // The rest ran out, and the next set came up in the dock with its own numbers.
        let (ni, ns) = try #require(once.current)
        draft.prepare(item: ni, set: ns, model: model)

        draft.undo(model: model)
        #expect(model.live?.items == before.items && model.live?.rest == before.rest)
        #expect(model.live?.current?.item == i && model.live?.current?.set == s)
        #expect(model.undoable == nil && model.floorContent == .set(item: i, set: s, kind: .rated))
        #expect(draft.setID == before.items[i].sets[s].id && draft.load == changed.load && draft.reps == changed.reps)
        // The dock or the floor coming up for it keeps them, and the same tap logs the same set.
        draft.prepare(item: i, set: s, model: model)
        draft.log(item: i, set: s, rating: .green, model: model)
        let again = try #require(model.live?.items[i])
        #expect(again.sets[s].logged?.loadKg == changed.load && again.sets[s].logged?.reps == changed.reps)
        #expect(again.sets.map(\.prescription) == once.items[i].sets.map(\.prescription))
    }

    @Test("Once every set is done, the last one can still be taken back")
    func undoTheLastSet() throws {
        let model = try atFirstWorkSet()
        let lift = try #require(model.live?.current?.item)
        // The main lift is all that's left.
        model.update { live in
            for index in live.items.indices where index != lift && !live.items[index].isDone { live.skip(item: index) }
        }
        for _ in 0..<20 where model.live?.current != nil { model.logNext(1) }
        #expect(model.live?.isComplete == true && model.floorContent == nil)
        let last = try #require(model.undoable)
        SetDraft().undo(model: model)
        #expect(model.live?.isComplete == false && model.undoable == nil)
        #expect(model.live?.current != nil, "\(last.text) is the set to do again")
    }

    @Test("The next set starts again from its own prescription")
    func nextSetStartsAgain() throws {
        let model = try atFirstWorkSet()
        let (i, s) = try #require(model.live?.current)
        let draft = SetDraft()
        draft.prepare(item: i, set: s, model: model)
        draft.load = 999
        draft.log(item: i, set: s, rating: .green, model: model)
        model.update { $0.endRest() }

        let (ni, ns) = try #require(model.live?.current)
        draft.prepare(item: ni, set: ns, model: model)
        let next = try #require(model.live?.items[ni].sets[ns])
        #expect(draft.setID == next.id)
        #expect(draft.reps == next.prescription.targetReps)
        #expect(draft.load != 999)
    }

    @Test("A timed set logs the time since a tap started its clock")
    func timedSet() throws {
        let model = TestApp().onboarded()
        model.start(try #require(model.plan()))
        // Through the session to the first set held for time (the warm-up's bike, a plank).
        for _ in 0..<60 {
            guard let live = model.live, let (i, s) = live.current else { break }
            if live.items[i].sets[s].prescription.seconds != nil, FloorSet(current: live, catalog: model.catalog) != nil { break }
            model.logNext(1)
            model.update { $0.endRest() }
        }
        let (ci, cs) = try #require(model.live?.current)
        let seconds = try #require(model.live?.items[ci].sets[cs].prescription.seconds)
        #expect(model.floorContent == .set(item: ci, set: cs, kind: .timed(seconds: seconds)))

        let draft = SetDraft()
        draft.prepare(item: ci, set: cs, model: model)
        draft.timerStart = Date().addingTimeInterval(-20)
        draft.logTimed(item: ci, set: cs, model: model)
        let logged = try #require(model.live?.items[ci].sets[cs].logged)
        #expect(logged.seconds == 20)
        #expect(logged.rating == nil)
        #expect(draft.timerStart == nil)
    }

    @Test("With every set done there's nothing for the floor, and the normal screen's Finish shows")
    func nothingLeft() throws {
        let model = try atFirstWorkSet()
        model.update { live in
            for index in live.items.indices { live.skip(item: index) }
            live.endRest()
        }
        #expect(model.floorContent == nil)
    }

    @Test("Floor mode is the iPhone's, and from the menu it's on at once")
    func turnedOnFromTheMenu() {
        let floor = FloorMode(launch: LaunchOptions(arguments: ["LiftTrack"]))
        floor.start(automatic: false)
        floor.turnOn()
        #expect(floor.isOn == Platform.hasFloorMode)
        floor.stop()
        #expect(!floor.isOn)
    }
}
