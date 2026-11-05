import Foundation
import NutritionEngine
import SystemCore

#if os(iOS)
import ActivityKit

/// Keeps a Live Activity in step with the running fast. The system ends a Live Activity after
/// about 8 hours, so one is started again whenever the app is opened while the fast runs.
@MainActor
enum FastActivityBridge {
    /// What an activity was last sent. The stale date counts for itself: a meal planned or removed
    /// within one phase changes when the activity goes out of date, and nothing it shows.
    struct Sent: Equatable {
        var state: FastActivityAttributes.ContentState
        var staleDate: Date?

        init(_ status: FastStatus, nextMeal: Date?) {
            state = FastActivityBridge.content(status)
            staleDate = FastActivityBridge.staleDate(state, nextMeal: nextMeal)
        }
    }

    private static var lastSent: Sent?

    static func update(_ model: AppModel) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard model.tracksMealTiming, let status = model.analysis?.fast else {
            end()
            return
        }
        let sent = Sent(status, nextMeal: model.foodLog.nextMeal(since: status.fast.start))
        let id = status.fast.id
        let live = Activity<FastActivityAttributes>.activities.filter { $0.activityState == .active }
        // Another fast's activity, left from before this one started. Activities aren't Sendable, so
        // they're found again off the main actor rather than handed over.
        if live.contains(where: { $0.attributes.id != id }) {
            Task.detached {
                for activity in Activity<FastActivityAttributes>.activities where activity.attributes.id != id {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
        // The system can't be told to end it when a meal logged for later comes, with the app closed:
        // at that time it reads as out of date, and the next open ends it.
        let content = ActivityContent(state: sent.state, staleDate: sent.staleDate)
        if !live.contains(where: { $0.attributes.id == id }) {
            do {
                let started = try Activity.request(attributes: FastActivityAttributes(id: id), content: content).id
                lastSent = sent
                // One the system ended (at 8 hours) can stay on the Lock Screen: it goes now the new one is up.
                Task.detached {
                    for activity in Activity<FastActivityAttributes>.activities where activity.attributes.id == id && activity.id != started {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                }
            } catch {
                // Only the app in front can start one; the next time it's opened it will.
                lastSent = nil
            }
        } else if sent != lastSent {
            lastSent = sent
            Task.detached {
                for activity in Activity<FastActivityAttributes>.activities where activity.attributes.id == id {
                    await activity.update(content)
                }
            }
        }
    }

    static func staleDate(_ state: FastActivityAttributes.ContentState, nextMeal: Date?) -> Date? {
        [state.nextPhaseAt, nextMeal].compactMap { $0 }.min()
    }

    static func end() {
        lastSent = nil
        guard !Activity<FastActivityAttributes>.activities.isEmpty else { return }
        Task.detached {
            for activity in Activity<FastActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    static func content(_ status: FastStatus) -> FastActivityAttributes.ContentState {
        FastActivityAttributes.ContentState(
            start: status.fast.start, goalEnd: status.fast.goalEnd, phase: status.phase.title, symbol: status.phase.symbol,
            nextPhase: status.phase.next?.title, nextPhaseAt: status.nextPhaseAt)
    }
}
#else
/// Live Activities are the iPhone's and the iPad's Lock Screen: the Mac and Vision Pro show the
/// fast on Today.
@MainActor
enum FastActivityBridge {
    static func update(_ model: AppModel) {}
    static func end() {}
}
#endif
