import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import Testing

@testable import LiftTrack

/// What a session led from the phone hands the Watch and Health, and what comes back from them: the
/// workout saved once and never lost, heart rate ending a rest, and Health's weight against the tape's.
@MainActor
@Suite("The Watch and Health")
struct WatchAndHealthTests {
    /// The Watch's mirrored workout and Health, as the model sees them, recording what it asks of them.
    @MainActor
    final class FakeWatch {
        var connected = true
        /// Whether a message gets to the Watch.
        var reachable = true
        /// What went over the mirrored workout.
        private(set) var sent: [MirrorMessage] = []
        /// What went over WatchConnectivity, the second route.
        private(set) var sentToApp: [MirrorMessage] = []
        private(set) var savedToHealth: [UUID] = []

        var handOff: AppModel.WorkoutHandOff {
            AppModel.WorkoutHandOff(
                watchConnected: { [self] in connected },
                sendToWatch: { [self] data in
                    if let message = MirrorMessage(encoded: data) { sent.append(message) }
                    return connected && reachable
                },
                saveToHealth: { [self] record in savedToHealth.append(record.id) },
                sendToWatchApp: { [self] data in
                    if let message = MirrorMessage(encoded: data) { sentToApp.append(message) }
                })
        }

        /// The copies of the session sent, oldest first, with the context when one came.
        var copies: [(session: LiveSession, context: PhoneContext?, sentAt: Date)] {
            sentToApp.compactMap {
                if case .session(let session, let context, let sentAt) = $0 { (session, context, sentAt) } else { nil }
            }
        }

        var finishedIDs: [UUID] {
            sent.compactMap {
                if case .finish(let id, _) = $0 { id } else { nil }
            }
        }

        var discards: Int {
            sent.filter {
                if case .discard = $0 { true } else { false }
            }.count
        }
    }

    /// An onboarded model with a session under way and a work set in it.
    private func sessionWithWork(_ watch: FakeWatch, saveToHealth: Bool = true) throws -> AppModel {
        let model = TestApp().onboarded(saveToHealth: saveToHealth)
        model.workoutHandOff = watch.handOff
        model.start(try #require(model.plan()))
        model.logUntilAWorkSet()
        return model
    }

    @Test("A Watch that gets the session's end saves the workout, and the phone doesn't save a second")
    func watchSavesTheWorkout() async throws {
        let watch = FakeWatch()
        let model = try sessionWithWork(watch)
        model.finish(feedback: nil)
        await model.workoutTask?.value
        let record = try #require(model.finished)
        #expect(watch.finishedIDs == [record.id])
        #expect(watch.savedToHealth.isEmpty)
        #expect(model.sessions.map(\.id) == [record.id])
    }

    @Test("When the session's end doesn't reach the Watch, the phone saves the workout instead")
    func phoneSavesWhenTheWatchMissesTheEnd() async throws {
        let watch = FakeWatch()
        watch.reachable = false
        let model = try sessionWithWork(watch)
        model.finish(feedback: nil)
        await model.workoutTask?.value
        let record = try #require(model.finished)
        #expect(watch.finishedIDs == [record.id])
        #expect(watch.savedToHealth == [record.id])
    }

    @Test("Without a Watch, the phone saves the workout")
    func phoneSavesWithoutAWatch() async throws {
        let watch = FakeWatch()
        watch.connected = false
        let model = try sessionWithWork(watch)
        model.finish(feedback: nil)
        await model.workoutTask?.value
        let record = try #require(model.finished)
        #expect(watch.sent.isEmpty)
        #expect(watch.savedToHealth == [record.id])
    }

    @Test("With Health off, or nothing logged, the Watch throws its workout away and nothing goes to Health")
    func watchDiscards() async throws {
        let watch = FakeWatch()
        let model = try sessionWithWork(watch, saveToHealth: false)
        model.finish(feedback: nil)
        await model.workoutTask?.value
        #expect(model.finished != nil)
        #expect(watch.discards == 1)
        #expect(watch.finishedIDs.isEmpty)
        #expect(watch.savedToHealth.isEmpty)

        let empty = FakeWatch()
        let nothing = TestApp().onboarded(saveToHealth: true)
        nothing.workoutHandOff = empty.handOff
        nothing.start(try #require(nothing.plan()))
        nothing.finish(feedback: nil)
        await nothing.workoutTask?.value
        #expect(nothing.finished == nil)
        #expect(empty.discards == 1)
        #expect(empty.savedToHealth.isEmpty)
    }

    @Test("A recovered heart rate ends a guided rest while it runs, and not once its time is up")
    func heartRateEndsTheRest() throws {
        let model = TestApp().onboarded()
        model.start(try #require(model.plan()))
        model.logUntilAWorkSet()
        let environment = try #require(model.environment)
        let item = try #require(model.live?.items.firstIndex { $0.plan.isStrength && !$0.loggedSets.isEmpty })
        let now = Date()
        func rest() {
            model.update { session in
                session.startRest(after: item, environment: environment, now: now)
                session.rest?.plan = RestPlan(target: 120, minimum: 0, heartRateGuided: true)
                session.rest?.endsAt = now.addingTimeInterval(120)
            }
        }
        func reading(at date: Date) throws -> Data { try #require(MirrorMessage.heartRate(bpm: 70, date: date).encoded()) }

        rest()
        model.fromWatch([try reading(at: now.addingTimeInterval(130))])
        #expect(model.live?.rest != nil, "Over already: the next set has the screen")

        model.fromWatch([try reading(at: now.addingTimeInterval(40))])
        #expect(model.live?.rest == nil)
    }

    @Test("A set logged on the Watch lands in the phone's session, and the copy that comes back says so")
    func setLoggedOnTheWatch() async throws {
        let watch = FakeWatch()
        let model = TestApp().onboarded()
        model.workoutHandOff = watch.handOff
        model.start(try #require(model.plan()))
        model.watchJoined()
        await model.watchShare?.value
        #expect(watch.copies.count == 1, "Starting and joining a moment apart send one copy")
        let first = try #require(watch.copies.last)
        let context = try #require(first.context, "The copy after joining carries the gym and loads")
        let environment = context.environment(catalog: model.catalog)
        var copy = MirroredSession(first.session, sentAt: first.sentAt)
        let (item, set) = try #require(copy.session.current)
        let kind = SessionChange.Kind.log(
            item: copy.session.items[item].id, set: set, reps: 5, loadKg: 40, rating: nil, seconds: 30, heartRatePeak: nil)
        _ = copy.make(kind, environment: environment)
        let message = try #require(MirrorMessage.changes(copy.pending).encoded())

        model.fromWatch([message])
        #expect(model.live?.items[item].sets[set].logged?.reps == 5)
        await model.watchShare?.value
        let back = try #require(watch.copies.last)
        #expect(watch.copies.count == 2)
        #expect(back.session.takenChanges == 1)
        #expect(back.context == nil, "The context goes once")
        let taken = copy.receive(back.session, sentAt: back.sentAt, environment: environment)
        #expect(taken && copy.pending.isEmpty)

        // The same change again (sent by both routes, or again because the copy was slow): logged once,
        // and the copy goes again so the Watch learns it landed.
        let before = try #require(model.live)
        model.fromWatch([message])
        await model.watchShare?.value
        #expect(model.live == before)
        #expect(watch.copies.count == 3)
    }

    @Test("An undo on the phone reaches the Watch in the next copy, which carries no undo; a set the Watch logs can't be undone here")
    func undoAndTheWatch() async throws {
        let watch = FakeWatch()
        let model = TestApp().onboarded()
        model.workoutHandOff = watch.handOff
        model.start(try #require(model.plan()))
        model.watchJoined()
        await model.watchShare?.value
        let context = try #require(watch.copies.last?.context)
        let environment = context.environment(catalog: model.catalog)
        let (item, set) = try #require(model.live?.current)

        model.logNext(1)
        await model.watchShare?.value
        #expect(model.live?.undoableSet?.set == set)
        #expect(watch.copies.last?.session.undo == nil)
        SetDraft().undo(model: model)
        await model.watchShare?.value
        let undone = try #require(watch.copies.last)
        #expect(undone.session.items[item].sets[set].isOpen)
        #expect(undone.session == model.live?.withoutHeartRate)

        // The Watch logs that set: it lands here, and there's nothing for the phone to undo.
        var copy = MirroredSession(undone.session, sentAt: undone.sentAt)
        let kind = SessionChange.Kind.log(
            item: copy.session.items[item].id, set: set, reps: 5, loadKg: 40, rating: nil, seconds: 30, heartRatePeak: nil)
        _ = copy.make(kind, environment: environment)
        model.fromWatch([try #require(MirrorMessage.changes(copy.pending).encoded())])
        #expect(model.live?.items[item].sets[set].logged?.reps == 5)
        #expect(model.undoable == nil)
    }

    @Test("When the mirrored workout drops, the Watch that joined still gets copies, and the session's end, the other way")
    func mirrorDrops() async throws {
        let watch = FakeWatch()
        let model = try sessionWithWork(watch)
        model.fromWatch([try #require(MirrorMessage.join.encoded())])
        await model.watchShare?.value
        // Out of range for a minute: the mirrored workout is gone, WatchConnectivity comes back.
        watch.connected = false
        let copies = watch.copies.count
        model.logNext(1)
        await model.watchShare?.value
        #expect(watch.copies.count == copies + 1)

        model.finish(feedback: nil)
        await model.workoutTask?.value
        let record = try #require(model.finished)
        // The phone saves the workout itself, and the Watch is told to throw its own away.
        #expect(watch.savedToHealth == [record.id])
        let told = watch.sentToApp.contains {
            if case .discard(let id, let saved) = $0 { id == record.id && saved } else { false }
        }
        #expect(told)
    }

    @Test("Ending the session on the Watch saves it on the phone with the Watch's feedback, once")
    func finishedOnTheWatch() async throws {
        let watch = FakeWatch()
        let model = try sessionWithWork(watch)
        let id = try #require(model.live?.id)
        let feedback = SessionFeedback(soreness: 2, jointPain: [.knee], energy: 4)
        let message = try #require(MirrorMessage.finishFromWatch(id: id, feedback: feedback).encoded())
        model.fromWatch([message])
        await model.workoutTask?.value
        let record = try #require(model.finished)
        #expect(record.id == id && model.live == nil)
        #expect(model.sessions.map(\.feedback) == [feedback])
        #expect(watch.finishedIDs == [id])
        #expect(watch.savedToHealth.isEmpty, "The Watch's workout is the one Health keeps")

        // The Watch didn't hear and asks again: it's told again, and nothing is saved twice.
        model.fromWatch([message])
        await model.workoutTask?.value
        #expect(watch.finishedIDs == [id, id])
        #expect(model.sessions.count == 1)
    }

    @Test("Discarding on the Watch discards the phone's session; a request for another session does nothing")
    func discardedOnTheWatch() async throws {
        let watch = FakeWatch()
        let model = try sessionWithWork(watch)
        let id = try #require(model.live?.id)
        model.fromWatch([try #require(MirrorMessage.discardFromWatch(id: UUID()).encoded())])
        model.fromWatch([try #require(MirrorMessage.finishFromWatch(id: UUID(), feedback: nil).encoded())])
        #expect(model.live?.id == id)

        model.fromWatch([try #require(MirrorMessage.discardFromWatch(id: id).encoded())])
        await model.workoutTask?.value
        #expect(model.live == nil && model.finished == nil && model.sessions.isEmpty)
        #expect(watch.discards == 1)
    }

    @Test("The session after today's is the program's next day, for a Watch left without the phone to go on to")
    func followingPlan() throws {
        let model = TestApp().onboarded()
        let next = try #require(model.analysis?.next)
        let plan = try #require(model.plan())
        let following = try #require(model.followingPlan())
        #expect(plan.dayID == next.day.id)
        #expect(following.dayID == next.followingDay.id && following.dayID != plan.dayID)
    }

    @Test("A weight typed on the tape after Health's last weigh-in counts, and Health's counts otherwise")
    func bodyweight() throws {
        // Onboarding typed 82 kg today.
        let model = TestApp().onboarded()
        model.bodyweightKg = 95
        model.bodyweightDate = Date().addingTimeInterval(-30 * 86_400)
        #expect(model.state?.measuredBodyweight == 82)
        #expect(model.state?.effectiveBodyweight == 82)

        model.bodyweightDate = Date()
        #expect(model.state?.measuredBodyweight == 95)
        model.bodyweightDate = nil
        #expect(model.state?.measuredBodyweight == 95)
    }
}
