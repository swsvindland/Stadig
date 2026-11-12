import Foundation
import SystemCore

/// When what's left of a session in progress should happen, from its plan: each exercise not yet
/// started and when the session is done. The iPad's scoreboard puts these beside the session's tape
/// ("Barbell Row 6:18", "Done by 6:48"). Each set costs what `SessionPlan.estimatedMinutes` gives
/// it, so the clock agrees with Today's "~57 min" before a set is done.
public struct SessionTimeline: Hashable, Sendable {
    /// When each exercise not yet started should start, by item id. A superset's partner starts
    /// with the exercise it's paired with.
    public var starts: [UUID: Date]
    /// When the last set should be done: the rest still to run, every open set with its rest, and
    /// none after the very last.
    public var doneBy: Date
}

extension PlannedItem {
    /// One open set's time: a warm-up a minute with its breather, a work set its reps (or its
    /// seconds) and the rest after it.
    func estimatedSeconds(of set: SetPrescription) -> (work: Int, rest: Int) {
        if set.kind == .warmup { return (60, 0) }
        return (seconds ?? (repRange.middle * 3 + 15), rest.target)
    }

    /// Getting set up for a lift: loading the bar, finding the bench.
    static let setupSeconds = 45
}

extension LiveSession {
    /// What's left, timed from `now`. The sauna or steam room is left out, as it is from the plan's
    /// length: it's optional and comes at the end.
    public func timeline(now: Date) -> SessionTimeline {
        var clock = now
        if let rest, rest.endsAt > now { clock = rest.endsAt }
        var starts: [UUID: Date] = [:]
        var groupStarts: [Int: Date] = [:]
        var lastRest = 0
        for item in items where !item.isDone && item.plan.block != .recovery {
            if item.sets.allSatisfy(\.isOpen) {
                if let group = item.plan.supersetGroup, let start = groupStarts[group] {
                    starts[item.id] = start
                } else {
                    starts[item.id] = clock
                    if let group = item.plan.supersetGroup { groupStarts[group] = clock }
                    if item.plan.isStrength { clock += TimeInterval(PlannedItem.setupSeconds) }
                }
            }
            if let conditioning = item.plan.conditioning {
                clock += TimeInterval(conditioning.minutes * 60)
                lastRest = 0
                continue
            }
            for set in item.sets where set.isOpen {
                let (work, rest) = item.plan.estimatedSeconds(of: set.prescription)
                clock += TimeInterval(work + rest)
                lastRest = rest
            }
        }
        return SessionTimeline(starts: starts, doneBy: clock - TimeInterval(lastRest))
    }
}
