import Foundation
import SystemCore

/// What widgets and complications show, written by the app to the App Group so they render
/// without opening the database.
nonisolated struct WidgetSnapshot: Codable, Hashable, Sendable {
    var title: String
    var detail: String
    var exercises: [String] = []
    var doneThisWeek = 0
    var plannedThisWeek = 0
    var minutes: Int?
    /// "Deload", "Assessment week 2", "Vacation".
    var badge: String?
    /// The day of the session shown (today's, or the next one on a rest day), so a widget drawn on a
    /// later day than the snapshot was written can say so. Nil before setup and in older snapshots.
    var day: Day?
    /// The first day of the week `doneThisWeek` counts.
    var weekStart: Day?
    var updated = Date()

    static let groupID = "group.dev.svindland.stadig"
    static let empty = WidgetSnapshot(title: "Stadig Lift", detail: "Open Stadig Lift to set up")
    static let sample = WidgetSnapshot(
        title: "Upper A", detail: "Week 2 · 2 reps in reserve",
        exercises: ["Barbell Bench Press", "Barbell Row", "Overhead Press", "Lat Pulldown"],
        doneThisWeek: 1, plannedThisWeek: 4, minutes: 60, badge: nil)

    /// Where the app and the Watch app write the snapshot and the widgets read it.
    static var appGroupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appending(path: "LiftTrack", directoryHint: .isDirectory).appending(path: "widget.json")
    }

    static func load(from url: URL? = appGroupURL) -> WidgetSnapshot {
        guard let url, let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    /// Returns whether it changed, so callers reload timelines only then.
    @discardableResult
    func save(to url: URL? = appGroupURL) -> Bool {
        guard let url else { return false }
        var mine = self
        mine.updated = .distantPast
        var old = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
        old?.updated = Date.distantPast
        guard old != mine else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
        return true
    }

    /// The iPhone snapshot as it reads on `today`, which can be days after the app wrote it: the
    /// session's day as "Today" or "Next: Thursday", a nudge to open the app once that day has gone
    /// by, and no sessions done yet in a new week.
    func reading(on today: Day) -> WidgetSnapshot {
        var snapshot = self
        if let day {
            if day == today {
                snapshot.detail = "Today"
            } else if day > today {
                snapshot.detail = "Next: \(day.date().formatted(.dateTime.weekday(.wide)))"
            } else {
                snapshot.detail = "Open Stadig Lift for today's plan"
                snapshot.minutes = nil
            }
        }
        if let weekStart, today >= weekStart.adding(days: 7) { snapshot.doneThisWeek = 0 }
        return snapshot
    }

    /// The Watch's snapshot as it reads on `today`: itself until its day has gone by, then a nudge to
    /// open the phone, which has the plan for the new day. Its wording ("Done today", "Rest day") is
    /// the Watch app's own, so only a stale one changes.
    func shown(on today: Day) -> WidgetSnapshot {
        guard let day, day < today else { return self }
        var snapshot = self
        snapshot.detail = "Open Stadig Lift on iPhone"
        snapshot.minutes = nil
        snapshot.exercises = []
        snapshot.badge = nil
        if let weekStart, today >= weekStart.adding(days: 7) { snapshot.doneThisWeek = 0 }
        return snapshot
    }
}
