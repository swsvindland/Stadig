import ExerciseLibrary
import Foundation
import LiftEngine
import Observation
import SwiftUI
import SystemCore

/// The set in front of you as the dock and Floor mode both have it: the load and reps (changed in
/// the dock before the phone is set down, they're what the floor logs) and a timed set's clock.
/// The session screen owns one; a new set starts again from its prescription.
@MainActor @Observable
final class SetDraft {
    /// The set the numbers are for.
    private(set) var setID: UUID?
    var load: Double = 0
    var reps = 0
    var timerStart: Date?

    /// Fills the load and reps for a set from its prescription, or a sensible starting guess when the
    /// person is picking a weight. The same set again keeps what's been changed.
    func prepare(item index: Int, set setIndex: Int, model: AppModel) {
        guard let live = model.live, live.items.indices.contains(index), live.items[index].sets.indices.contains(setIndex) else { return }
        let item = live.items[index]
        let set = item.sets[setIndex]
        guard setID != set.id else { return }
        setID = set.id
        reps = set.prescription.targetReps
        load = model.startingLoad(for: set, at: setIndex, of: item, exercise: model.catalog.resolve(item.exerciseID))
        timerStart = nil
    }

    /// Logs the set with these numbers and a rating (none for a warm-up or a rep-out): the dock's
    /// rating buttons, Done and "Log 9 reps", and the floor's tap and swipes, so a gesture is a button.
    func log(item index: Int, set setIndex: Int, rating: SetRating?, model: AppModel) {
        guard let live = model.live, live.items.indices.contains(index) else { return }
        let exercise = model.catalog.resolve(live.items[index].exerciseID)
        let environment = model.sessionEnvironment
        let (reps, load) = (reps, load)
        model.update { live in
            live.log(
                item: index, set: setIndex, reps: reps, loadKg: exercise.loadBasis == .none ? 0 : load, rating: rating,
                environment: environment, now: Date())
        }
        AccessibilityNotification.Announcement(model.live?.message ?? "Logged").post()
    }

    /// Logs a timed set or a drill's reps: the time since its clock started, or what was prescribed.
    func logTimed(item index: Int, set setIndex: Int, model: AppModel) {
        guard let live = model.live, live.items.indices.contains(index), live.items[index].sets.indices.contains(setIndex) else { return }
        let prescription = live.items[index].sets[setIndex].prescription
        let elapsed = timerStart.map { Int(Date().timeIntervalSince($0)) }
        let environment = model.sessionEnvironment
        model.update { live in
            live.log(
                item: index, set: setIndex, reps: prescription.targetReps, loadKg: nil, rating: nil,
                seconds: elapsed ?? prescription.seconds, environment: environment, now: Date())
        }
        timerStart = nil
    }

    /// Takes back the set just logged (Undo in the rest, on the floor and on the scoreboard): the
    /// session puts it back as it was (`LiveSession.undoLastSet`), and the numbers here are the ones
    /// it was logged with, so logging it again is one tap even after the next set's were filled in.
    func undo(model: AppModel) {
        guard let live = model.live, let (item, set, logged) = live.undoableSet else { return }
        let name = model.justLogged(item: item, set: set)?.name ?? "Set"
        model.update { $0.undoLastSet() }
        setID = live.items[item].sets[set].id
        load = logged.loadKg
        reps = logged.reps
        timerStart = nil
        AccessibilityNotification.Announcement("\(name) undone").post()
    }
}

/// The set a rest follows, as the rest names it ("Set 2 logged · Just right"), and whether Undo
/// takes it back.
struct JustLogged: Equatable {
    /// "Set 2", "Warm-up".
    var name: String
    var rating: SetRating?
    /// The rating, or a rep-out's reps.
    var detail: String?
    var undoable: Bool

    /// "Set 2 logged · Just right".
    var text: String { "\(name) logged" + (detail.map { " · \($0)" } ?? "") }
}

extension AppModel {
    /// The set last logged in an exercise (the one a rest follows), or nil when none is.
    func justLogged(after rest: RestState) -> JustLogged? {
        guard let live, let index = live.item(rest.itemID) else { return nil }
        let sets = live.items[index].sets
        let logged = sets.indices.filter { sets[$0].logged != nil }
        guard let set = logged.max(by: { (sets[$0].logged?.date ?? .distantPast) < (sets[$1].logged?.date ?? .distantPast) }) else { return nil }
        return justLogged(item: index, set: set)
    }

    /// The set Undo would take back, when there's one: what the dock shows once every set is done.
    var undoable: JustLogged? {
        guard let live, let (item, set, _) = live.undoableSet else { return nil }
        return justLogged(item: item, set: set)
    }

    func justLogged(item index: Int, set: Int) -> JustLogged? {
        guard let live, live.items.indices.contains(index), live.items[index].sets.indices.contains(set),
            let logged = live.items[index].sets[set].logged
        else { return nil }
        let sets = live.items[index].sets
        let undoable = live.undoableSet.map { $0.item == index && $0.set == set } ?? false
        if logged.kind == .warmup { return JustLogged(name: "Warm-up", undoable: undoable) }
        let number = sets[...set].filter { $0.prescription.kind != .warmup }.count
        let detail = logged.rating?.label ?? (logged.kind == .repOut ? "\(logged.reps) reps" : nil)
        return JustLogged(name: "Set \(number)", rating: logged.rating, detail: detail, undoable: undoable)
    }
}

extension AppModel {
    /// What a set is logged against: the analysis's, or a neutral one before there is any.
    var sessionEnvironment: SessionEnvironment {
        environment
            ?? SessionEnvironment(
                catalog: catalog, gym: gym, trust: TrustState(prior: 0.5), phase: NutritionPhase.assumedMaintenance.effects,
                bodyweightKg: nil, history: [:], enduranceScore: nil, heartRateGuidedRest: false)
    }
}
