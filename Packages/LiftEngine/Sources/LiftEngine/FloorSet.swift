import ExerciseLibrary
import Foundation
import SystemCore

/// What Floor mode's three gestures (tap anywhere, swipe up, swipe down) do to the set in front of
/// you. Each is one of the dock's buttons for the same set, so logging from the floor is logging
/// from the dock.
public enum FloorSet: Sendable, Hashable {
    /// A work set to rate: a tap is Just right, a swipe up Easy, a swipe down Missed.
    case rated
    /// A warm-up: a tap logs it, unrated, as the dock's Done does.
    case warmup
    /// As many as you can: the swipes count the reps up and down, and a tap logs them.
    case repOut
    /// Held for time: a tap starts the clock and the next one logs it.
    case timed(seconds: Int)
    /// Reps with nothing to rate, a drill's: a tap logs them.
    case done

    /// What the gestures do for this set, or nil where they don't fit and the session keeps its
    /// normal screen: a conditioning piece (its clock, its zones and minutes) and the sauna (a
    /// thermometer first and a rating after).
    public init?(item: LiveItem, set: LiveSet, exercise: Exercise) {
        if item.plan.conditioning != nil || item.plan.role == .recovery { return nil }
        if !item.plan.isStrength || exercise.timed {
            self = set.prescription.seconds.map { .timed(seconds: $0) } ?? .done
            return
        }
        switch set.prescription.kind {
        case .warmup: self = .warmup
        case .repOut: self = .repOut
        default: self = .rated
        }
    }

    /// The set in front of you in a session, or nil when there's none or it doesn't fit.
    public init?(current live: LiveSession, catalog: ExerciseCatalog) {
        guard let (index, setIndex) = live.current, live.items.indices.contains(index),
            live.items[index].sets.indices.contains(setIndex)
        else { return nil }
        let item = live.items[index]
        self.init(item: item, set: item.sets[setIndex], exercise: catalog.resolve(item.exerciseID))
    }

    /// Whether swiping up and down does anything: a rating, or a rep-out's count.
    public var swipes: Bool {
        switch self {
        case .rated, .repOut: true
        case .warmup, .timed, .done: false
        }
    }
}
