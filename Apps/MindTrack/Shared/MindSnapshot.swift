import Foundation
import SystemCore

/// What the widgets show: today's study at a glance. Written by the app to the App Group so they
/// render without opening the database or the catalogs.
nonisolated struct MindSnapshot: Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        /// Not set up yet.
        case setUp
        /// A session waits today.
        case today
        /// Today's session is done.
        case done
        /// Nothing planned today.
        case rest
        /// Vacation, illness or crunch: studying is paused.
        case paused
    }

    /// One part of today's session, as Today lists it.
    struct Part: Codable, Hashable, Sendable {
        var title: String
        var minutes: Int
        var symbol: String
    }

    var status: Status
    /// "Japanese · 25 min", "Done for today", "Rest day", "Vacation".
    var headline: String
    /// The week's phase: "Week 2 of 5", "Review week".
    var phase: String
    var parts: [Part] = []
    /// The domains' symbols, for the badges along the top.
    var symbols: [String] = []
    var doneThisWeek = 0
    var plannedThisWeek = 0
    /// Cards due for review today.
    var dueReviews = 0
    /// The next study day this week, when today has none left.
    var nextDay: Day?
    /// The last day `phase` (and a pause) holds; nil for a pause with no end set.
    var phaseLastDay: Day?
    /// The day the snapshot was written for, so a widget drawn days later can say it's stale.
    var day: Day?
    var updated = Date()

    static let groupID = "group.dev.svindland.stadig"
    static let empty = MindSnapshot(status: .setUp, headline: "Open Mind Track to set up", phase: "Mind Track")
    static let sample = MindSnapshot(
        status: .today, headline: "Japanese and maths · 25 min", phase: "Week 2 of 5",
        parts: [
            Part(title: "Reviews", minutes: 5, symbol: "arrow.triangle.2.circlepath"),
            Part(title: "Japanese", minutes: 12, symbol: "character.book.closed.ja"),
            Part(title: "Maths", minutes: 8, symbol: "function"),
        ],
        symbols: ["character.book.closed.ja", "function"], doneThisWeek: 2, plannedThisWeek: 5, dueReviews: 18)

    /// Where the app writes the snapshot and the widgets read it.
    static var appGroupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appending(path: "MindTrack", directoryHint: .isDirectory).appending(path: "widget.json")
    }

    static func load(from url: URL? = appGroupURL) -> MindSnapshot {
        guard let url, let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder().decode(MindSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    /// Writes the snapshot unless the file already says the same; returns whether it wrote, so the
    /// app reloads the widgets only then.
    @discardableResult
    func save(to url: URL? = appGroupURL) throws -> Bool {
        guard let url else { return false }
        var mine = self
        mine.updated = .distantPast
        var old = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(MindSnapshot.self, from: $0) }
        old?.updated = .distantPast
        guard old != mine else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        return true
    }

    /// The snapshot as it reads on `today`, which can be days after the app wrote it. Once its day
    /// has gone by it says only what it still knows: a pause that hasn't ended (or has no end set)
    /// is still a pause, a day before the next study day is a rest day, the next study day nudges
    /// to open the app, and past that it just asks. The day's parts and courses go, the phase goes
    /// once it's over, and a new week counts from zero.
    func reading(on today: Day) -> MindSnapshot {
        guard let day, day < today, status != .setUp else { return self }
        var snapshot = self
        snapshot.parts = []
        snapshot.symbols = []
        snapshot.dueReviews = 0
        if today >= day.startOfWeek.adding(days: 7) { snapshot.doneThisWeek = 0 }
        // A pause with no end set holds until the app says otherwise; any other phase without a
        // last day (a snapshot from before it was kept) isn't trusted.
        let phaseHolds = phaseLastDay.map { today <= $0 } ?? (status == .paused)
        if !phaseHolds { snapshot.phase = Self.empty.phase }
        if status == .paused, phaseHolds { return snapshot }
        if let nextDay, nextDay > today {
            snapshot.status = .rest
            snapshot.headline = "Rest day"
        } else if nextDay == today {
            snapshot.status = .today
            snapshot.headline = "Study day: open Mind Track"
        } else {
            snapshot.status = .today
            snapshot.headline = "Open Mind Track for today's plan"
        }
        return snapshot
    }

    /// Where tapping the widget goes: straight into the session when one waits, else Today. Read
    /// from the snapshot as it reads on the day drawn, not as written.
    var link: URL? { URL(string: status == .today ? "mindtrack://start" : "mindtrack://today") }
}
