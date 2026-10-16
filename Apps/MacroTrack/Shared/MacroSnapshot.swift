import Foundation

/// What the widgets show, written by the app to the App Group so they render without opening the
/// database.
nonisolated struct MacroSnapshot: Codable, Hashable, Sendable {
    /// The day the numbers are for (ISO), so a widget past midnight shows a fresh day.
    var day: String
    var kcal: Double = 0
    var kcalTarget: Double?
    var protein: Double = 0
    var proteinTarget: Double?
    var carbs: Double = 0
    var carbsTarget: Double?
    var fat: Double = 0
    var fatTarget: Double?
    /// "Day 5 of 21", "Diet break", "Vacation".
    var badge: String?
    var weighedToday = false
    var updated = Date()

    static let groupID = "group.dev.svindland.system"
    static let empty = MacroSnapshot(day: "")
    static let sample = MacroSnapshot(day: isoDay(Date()), kcal: 1240, kcalTarget: 2300, protein: 96, proteinTarget: 170, carbs: 130,
                                      carbsTarget: 240, fat: 42, fatTarget: 70, badge: nil, weighedToday: true)

    /// Today's view of it: eaten resets to nothing once the day it was written for has passed.
    func current(now: Date = Date()) -> MacroSnapshot {
        guard day != Self.isoDay(now) else { return self }
        var fresh = self
        fresh.day = Self.isoDay(now)
        fresh.kcal = 0
        fresh.protein = 0
        fresh.carbs = 0
        fresh.fat = 0
        fresh.weighedToday = false
        return fresh
    }

    var kcalLeft: Double? { kcalTarget.map { $0 - kcal } }
    var proteinLeft: Double? { proteinTarget.map { $0 - protein } }

    static func isoDay(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appending(path: "MacroTrack", directoryHint: .isDirectory).appending(path: "widget.json")
    }

    static func load() -> MacroSnapshot {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(MacroSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    /// Returns whether it changed, so callers reload timelines only then.
    @discardableResult
    func save() -> Bool {
        guard let url = Self.url else { return false }
        var mine = self
        mine.updated = .distantPast
        var old = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(MacroSnapshot.self, from: $0) }
        old?.updated = .distantPast
        guard old != mine else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
        return true
    }
}
