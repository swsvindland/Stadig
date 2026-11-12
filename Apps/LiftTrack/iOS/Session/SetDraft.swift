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
