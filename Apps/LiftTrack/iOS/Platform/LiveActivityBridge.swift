import ActivityKit
import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore

/// Keeps the session's Live Activity in step with the live session.
@MainActor
enum LiveActivityBridge {
    private static var started = false
    private static var lastState: SessionActivityAttributes.ContentState?

    /// Tests and UI tests start no Live Activity: it would outlive the test on the Lock Screen.
    private static var enabled: Bool { !LaunchOptions.current.isQuiet }

    static func update(_ session: LiveSession?, catalog: ExerciseCatalog, unit: WeightUnit) {
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let session, !session.isComplete else {
            end()
            return
        }
        let state = content(session, catalog: catalog, unit: unit)
        guard state != lastState else { return }
        lastState = state
        let content = ActivityContent(state: state, staleDate: state.restEndsAt?.addingTimeInterval(600))
        if started {
            // Activities aren't Sendable; update them from outside the main actor.
            Task.detached {
                for activity in Activity<SessionActivityAttributes>.activities { await activity.update(content) }
            }
        } else {
            started = (try? Activity.request(attributes: SessionActivityAttributes(title: session.plan.title), content: content)) != nil
        }
    }

    /// After a relaunch: adopt an activity left running, or end it when the session is gone.
    static func resume(_ session: LiveSession?, catalog: ExerciseCatalog, unit: WeightUnit) {
        guard enabled else { return }
        started = !Activity<SessionActivityAttributes>.activities.isEmpty
        if session == nil { end() } else { update(session, catalog: catalog, unit: unit) }
    }

    static func end() {
        guard started else { return }
        started = false
        lastState = nil
        Task.detached {
            for activity in Activity<SessionActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// What the Lock Screen shows for the session: the exercise, the set ("Warm-up", "Set 2 of 3")
    /// with its target, and the rest while it runs.
    static func content(_ session: LiveSession, catalog: ExerciseCatalog, unit: WeightUnit, now: Date = Date())
        -> SessionActivityAttributes.ContentState
    {
        var exercise = "Finish session"
        var detail = ""
        if let current = session.current {
            let item = session.items[current.item]
            let e = catalog.resolve(item.exerciseID)
            exercise = e.name
            let set = item.sets[current.set]
            let work = item.sets.filter { $0.prescription.kind != .warmup }
            let index = item.sets[...current.set].filter { $0.prescription.kind != .warmup }.count
            let label = set.prescription.kind == .warmup ? "Warm-up" : "Set \(index) of \(work.count)"
            detail = "\(label) · \(Format.set(set.prescription, exercise: e, unit: unit))"
        }
        let rest = session.rest.flatMap { $0.endsAt > now ? $0.endsAt : nil }
        return SessionActivityAttributes.ContentState(
            exercise: exercise, detail: detail, restEndsAt: rest,
            message: rest == nil ? nil : session.message, progress: session.progress)
    }
}
