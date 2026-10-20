import Foundation
import NutritionEngine
import OSLog
import SystemCore
import UserNotifications

/// A notification at each phase of the running fast from 12 hours on, and at its goal. Ending the
/// fast (or a meal ending it, on any device) takes the rest away.
enum FastReminders {
    nonisolated static let category = "fast"
    private static let prefix = "fast-"
    /// What was last scheduled, so an unchanged fast doesn't touch the notification center.
    @MainActor private static var scheduled: [String: String]?
    @MainActor private static var latest: [String: FastMilestone] = [:]
    @MainActor private static var running: Task<Void, Never>?

    /// The notifications wanted, by identifier: the running fast's milestones still to come. None
    /// while alerts or meal timing are off.
    @MainActor
    static func wanted(_ model: AppModel, now: Date = Date()) -> [String: FastMilestone] {
        guard model.tracksMealTiming, model.fastAlerts, let fast = model.analysis?.fast?.fast else { return [:] }
        var wanted: [String: FastMilestone] = [:]
        for (index, milestone) in Fasting.milestones(fast).enumerated() where milestone.at > now {
            // The time is in the id, so a changed goal or start replaces the notification.
            wanted["\(prefix)\(fast.id.uuidString)-\(index)-\(Int(milestone.at.timeIntervalSince1970))"] = milestone
        }
        return wanted
    }

    @MainActor
    static func schedule(_ model: AppModel) {
        let wanted = wanted(model)
        let signature = wanted.mapValues { "\($0.at.timeIntervalSince1970)|\($0.title)" }
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

    @MainActor
    private static func apply() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        let wanted = latest
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { wanted[$0] == nil })
        for (id, milestone) in wanted where !pending.contains(id) {
            if Task.isCancelled { return }
            let content = UNMutableNotificationContent()
            content.title = milestone.title
            content.body = milestone.body
            content.sound = .default
            content.categoryIdentifier = category
            content.threadIdentifier = "fast"
            let interval = milestone.at.timeIntervalSinceNow
            guard interval > 1 else { continue }
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
            } catch {
                scheduled = nil
                appLog.error("Couldn't schedule a fast notification: \(error.localizedDescription)")
            }
        }
    }
}
