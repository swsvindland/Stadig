import Foundation
import NutritionEngine
import OSLog
import SystemCore
import UserNotifications

/// A reminder at each time of day with doses due, for the next few days, with a Taken button that
/// ticks them off without opening the app. A time whose doses are all marked loses its reminder.
enum SupplementReminders {
    nonisolated static let category = "supplement-doses"
    nonisolated static let takenAction = "taken"
    private static let prefix = "dose-"
    /// The reminders last scheduled, so an unchanged plan doesn't touch the notification center.
    @MainActor private static var scheduled: [String: String]?
    /// The newest plan, and the run applying it. Runs go one at a time and each applies the newest
    /// plan, so two quick ticks can't interleave and bring back a reminder the second one removed.
    @MainActor private static var latest: [String: Reminder] = [:]
    @MainActor private static var running: Task<Void, Never>?

    struct Reminder: Hashable, Sendable {
        var date: Date
        var body: String
        var time: DoseTime
        var day: Day
    }

    static func register() {
        let taken = UNNotificationAction(
            identifier: takenAction, title: "Taken", options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let category = UNNotificationCategory(identifier: category, actions: [taken], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
    }

    static func requestPermission() async -> Bool {
        // Tests and UI tests never see the prompt; nothing is scheduled there anyway.
        if LaunchOptions.current.isQuiet { return true }
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            appLog.error("Couldn't ask to send reminders: \(error.localizedDescription)")
            return false
        }
    }

    /// The reminders wanted, by identifier: each time of day with doses still open, today and the
    /// next two days, from now on. None while reminders are off.
    @MainActor
    static func wanted(_ model: AppModel, now: Date = Date(), timeZone: TimeZone = .current) -> [String: Reminder] {
        var wanted: [String: Reminder] = [:]
        guard model.settings.supplementReminders == true else { return wanted }
        for offset in 0..<3 {
            let day = model.today.adding(days: offset)
            let doses = model.doses(on: day)
            for time in DoseTime.allCases {
                let open = doses.filter { $0.dose.time == time && $0.open }
                guard !open.isEmpty else { continue }
                let date = day.at(minutes: model.settings.minutes(time), timeZone: timeZone)
                guard date > now else { continue }
                let names = open.map { "\($0.supplement.name) (\($0.supplement.facts.amountLabel($0.dose.count)))" }
                wanted["\(prefix)\(day.iso)-\(time.rawValue)"] = Reminder(date: date, body: names.joined(separator: ", "), time: time, day: day)
            }
        }
        return wanted
    }

    @MainActor
    static func schedule(_ model: AppModel) {
        let wanted = wanted(model)
        let signature = wanted.mapValues { "\($0.date.timeIntervalSince1970)|\($0.body)" }
        guard signature != scheduled else { return }
        scheduled = signature
        latest = wanted
        let previous = running
        previous?.cancel()
        running = Task {
            await previous?.value
            await apply()
        }
    }

    /// Makes the pending reminders match the newest plan.
    @MainActor
    private static func apply() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        // Read after the wait: a newer plan may have come in meanwhile.
        let wanted = latest
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { wanted[$0] == nil })
        for (id, reminder) in wanted {
            // A newer plan is waiting to run, and will add what it wants.
            if Task.isCancelled { return }
            let content = UNMutableNotificationContent()
            content.title = "\(reminder.time.label) supplements"
            content.body = reminder.body
            content.sound = .default
            content.categoryIdentifier = category
            content.userInfo = ["day": reminder.day.iso, "time": reminder.time.rawValue]
            content.threadIdentifier = "supplements"
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: id, content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            } catch {
                // Tried again at the next change rather than counted as scheduled.
                scheduled = nil
                appLog.error("Couldn't schedule a supplement reminder: \(error.localizedDescription)")
            }
        }
    }
}

/// Handles a reminder's Taken button (in the background) and a tap on it (Today, at that day's
/// supplements) or on a fast's notification (Today).
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationHandler()

    /// On the main actor (the app's default), not nonisolated: the system's completion handler is
    /// called wherever this returns, and UIKit stops the app when a response's handler is called
    /// off the main thread. Nonisolated, every tap on a reminder crashed the app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let model = AppModel.shared
        // Opened, or woken for the Taken button, on a later day than the app last ran.
        model.refreshDay()
        if content.categoryIdentifier == FastReminders.category {
            model.selectedDay = model.today
            model.tab = .today
            return
        }
        guard content.categoryIdentifier == SupplementReminders.category,
            let iso = content.userInfo["day"] as? String, let day = Day(iso: iso),
            let raw = content.userInfo["time"] as? String, let time = DoseTime(rawValue: raw)
        else { return }
        if response.actionIdentifier == SupplementReminders.takenAction {
            _ = model.takeAll(at: time, on: day)
        } else {
            model.showDoses(on: day)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions
    {
        [.banner, .list, .sound]
    }
}
