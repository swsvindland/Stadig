import Foundation
import UIKit
import UserNotifications
import WidgetKit
import ExerciseLibrary
import LiftEngine
import SystemCore

/// Keeps the widgets' snapshot current.
enum WidgetBridge {
    @MainActor
    static func update(_ model: AppModel) {
        guard let analysis = model.analysis else { return }
        var snapshot = WidgetSnapshot.empty
        if let next = analysis.next {
            snapshot.title = next.day.name
            let week = next.mesocycle.block.week(of: model.today)
            switch week {
            case .deload: snapshot.badge = "Deload"
            case .loading(let w) where next.mesocycle.block.kind == .assessment: snapshot.badge = "Assessment week \(w + 1)"
            default: break
            }
            if !analysis.life.trainingExpected {
                snapshot.badge = analysis.life.active.first?.kind.label
            }
            snapshot.detail = next.scheduledToday ? "Today" : (next.nextDay.map { "Next: \(Format.day($0, style: .dateTime.weekday(.wide)))" } ?? "Up next")
            snapshot.exercises = next.day.strengthSlots.prefix(5).map { model.catalog.resolve($0.exerciseID).name }
            snapshot.doneThisWeek = next.doneThisWeek
            snapshot.plannedThisWeek = next.plannedThisWeek
            snapshot.minutes = next.day.minutes
        }
        if snapshot.save() { WidgetCenter.shared.reloadAllTimelines() }
    }
}

/// A local notification when rest ends with the phone in a pocket.
@MainActor
final class RestAlerts {
    static let shared = RestAlerts()
    private let id = "rest-over"
    private var asked = false

    func requestPermission() {
        guard !asked else { return }
        asked = true
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    func schedule(for rest: RestState?, catalog: ExerciseCatalog, session: LiveSession) {
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
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Heart rate came back down before the timer: rest's over now, with a tap to say so.
    func heartRateRecovered() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let content = UNMutableNotificationContent()
        content.title = "Heart rate's back down"
        content.body = "Ready for the next set."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
