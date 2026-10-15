import Foundation

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
    var updated = Date()

    static let groupID = "group.dev.svindland.system"
    static let empty = WidgetSnapshot(title: "Lift Track", detail: "Open Lift Track to set up")
    static let sample = WidgetSnapshot(title: "Upper A", detail: "Week 2 · 2 reps in reserve",
                                       exercises: ["Barbell Bench Press", "Barbell Row", "Overhead Press", "Lat Pulldown"],
                                       doneThisWeek: 1, plannedThisWeek: 4, minutes: 60, badge: nil)

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appending(path: "LiftTrack", directoryHint: .isDirectory).appending(path: "widget.json")
    }

    static func load() -> WidgetSnapshot {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    /// Returns whether it changed, so callers reload timelines only then.
    @discardableResult
    func save() -> Bool {
        guard let url = Self.url else { return false }
        var mine = self
        mine.updated = .distantPast
        var old = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
        old?.updated = Date.distantPast
        guard old != mine else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
        return true
    }
}
