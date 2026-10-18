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
        private(set) var sent: [MirrorMessage] = []
        private(set) var savedToHealth: [UUID] = []

        var handOff: AppModel.WorkoutHandOff {
            AppModel.WorkoutHandOff(
                watchConnected: { [self] in connected },
                sendToWatch: { [self] data in
                    if let message = try? JSONDecoder().decode(MirrorMessage.self, from: data) { sent.append(message) }
                    return connected && reachable
                },
                saveToHealth: { [self] record in savedToHealth.append(record.id) })
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
        func reading(at date: Date) throws -> Data { try JSONEncoder().encode(MirrorMessage.heartRate(bpm: 70, date: date)) }

        rest()
        model.fromWatch([try reading(at: now.addingTimeInterval(130))])
        #expect(model.live?.rest != nil, "Over already: the next set has the screen")

        model.fromWatch([try reading(at: now.addingTimeInterval(40))])
        #expect(model.live?.rest == nil)
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
