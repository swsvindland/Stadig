import Foundation
import UserNotifications
import NutritionEngine
import SystemCore

/// A reminder at each time of day with doses due, for the next few days, with a Taken button that
/// ticks them off without opening the app. A time whose doses are all marked loses its reminder.
enum SupplementReminders {
    nonisolated static let category = "supplement-doses"
    nonisolated static let takenAction = "taken"
    private static let prefix = "dose-"
    /// The reminders last scheduled, so an unchanged plan doesn't touch the notification center.
    @MainActor private static var scheduled: [String: String]?

    static func register() {
        let taken = UNNotificationAction(identifier: takenAction, title: "Taken", options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let category = UNNotificationCategory(identifier: category, actions: [taken], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    @MainActor
    static func schedule(_ model: AppModel) {
        var wanted: [String: (date: Date, body: String, time: DoseTime, day: Day)] = [:]
        if model.settings.supplementReminders == true {
            let now = Date()
            for offset in 0..<3 {
                let day = model.today.adding(days: offset)
                let doses = model.doses(on: day)
                for time in DoseTime.allCases {
                    let open = doses.filter { $0.dose.time == time && $0.open }
                    guard !open.isEmpty else { continue }
                    let date = day.date().addingTimeInterval(Double(model.settings.minutes(time)) * 60)
                    guard date > now else { continue }
                    let names = open.map { "\($0.supplement.name) (\($0.supplement.facts.amountLabel($0.dose.count)))" }
                    wanted["\(prefix)\(day.iso)-\(time.rawValue)"] = (date, names.joined(separator: ", "), time, day)
                }
            }
        }
        let signature = wanted.mapValues { "\($0.date.timeIntervalSince1970)|\($0.body)" }
        guard signature != scheduled else { return }
        scheduled = signature
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { wanted[$0] == nil })
            for (id, reminder) in wanted {
                let content = UNMutableNotificationContent()
                content.title = "\(reminder.time.label) supplements"
                content.body = reminder.body
                content.sound = .default
                content.categoryIdentifier = category
                content.userInfo = ["day": reminder.day.iso, "time": reminder.time.rawValue]
                content.threadIdentifier = "supplements"
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
                try? await center.add(UNNotificationRequest(identifier: id, content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }
}

/// Handles a reminder's Taken button (in the background) and a tap on it (opens Today).
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationHandler()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard response.notification.request.content.categoryIdentifier == SupplementReminders.category,
              let iso = info["day"] as? String, let day = Day(iso: iso),
              let raw = info["time"] as? String, let time = DoseTime(rawValue: raw) else { return }
        let taken = response.actionIdentifier == SupplementReminders.takenAction
        await MainActor.run {
            let model = AppModel.shared
            if taken {
                model.reloadIfChanged()
                _ = model.takeAll(at: time, on: day)
            } else {
                model.selectedDay = day
                model.tab = .today
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
