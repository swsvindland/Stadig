import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import UserNotifications
import WidgetKit

#if os(iOS)
import UIKit
#endif

/// Keeps the widgets' snapshot current.
enum WidgetBridge {
    @MainActor
    static func update(_ model: AppModel) {
        guard let snapshot = snapshot(for: model), let url = model.widgetURL else { return }
        if snapshot.save(to: url), url == WidgetSnapshot.appGroupURL { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// What the widgets show for the model as it stands: nil before setup, when there's nothing to say.
    @MainActor
    static func snapshot(for model: AppModel) -> WidgetSnapshot? {
        guard let analysis = model.analysis else { return nil }
        var snapshot = WidgetSnapshot.empty
        if let next = analysis.next {
            // The session as Today has it: the planner's swaps for an injury or missing gear, crunch
            // mode's minutes.
            let plan = model.plan()
            snapshot.title = plan?.title ?? next.day.name
            let week = next.mesocycle.block.week(of: model.today)
            switch week {
            case .deload: snapshot.badge = "Deload"
            case .loading(let w) where next.mesocycle.block.kind == .assessment: snapshot.badge = "Assessment week \(w + 1)"
            default: break
            }
            if !analysis.life.trainingExpected {
                snapshot.badge = analysis.life.active.first?.kind.label
            }
            snapshot.day = next.scheduledToday ? model.today : next.nextDay
            snapshot.weekStart = model.today.startOfWeek
            snapshot.detail =
                next.scheduledToday ? "Today" : (next.nextDay.map { "Next: \(Format.day($0, style: .dateTime.weekday(.wide)))" } ?? "Up next")
            let exercises = plan.map { $0.items.filter(\.isStrength).map(\.exerciseID) } ?? next.day.strengthSlots.map(\.exerciseID)
            snapshot.exercises = exercises.prefix(5).map { model.catalog.resolve($0).name }
            snapshot.doneThisWeek = next.doneThisWeek
            snapshot.plannedThisWeek = next.plannedThisWeek
            snapshot.minutes = plan?.estimatedMinutes ?? next.day.minutes
        }
        return snapshot
    }
}

/// A local notification when rest ends with the phone in a pocket.
@MainActor
final class RestAlerts {
    static let shared = RestAlerts()
    private let id = "rest-over"
    private var asked = false

    func requestPermission() {
        // Tests and UI tests: no permission prompts.
        guard !asked, !LaunchOptions.current.isQuiet else { return }
        asked = true
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    func schedule(for rest: RestState?, catalog: ExerciseCatalog, session: LiveSession) {
        // Never asked under tests, so nothing to show.
        guard !LaunchOptions.current.isQuiet else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let rest, rest.endsAt > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest's up"
        if let current = session.current {
            let item = session.items[current.item]
            content.body = "Next: \(catalog.resolve(item.exerciseID).name)"
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, rest.endsAt.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancel() {
        guard !LaunchOptions.current.isQuiet else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Heart rate came back down before the timer: rest's over now, with a tap to say so.
    func heartRateRecovered() {
        guard !LaunchOptions.current.isQuiet else { return }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        let content = UNMutableNotificationContent()
        content.title = "Heart rate's back down"
        content.body = "Ready for the next set."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
