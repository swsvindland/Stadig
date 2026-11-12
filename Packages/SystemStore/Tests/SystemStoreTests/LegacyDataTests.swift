import Foundation
import SystemCore
import Testing

@testable import SystemStore

/// Stadig Mind and the hub left the family, but devices still hold what they published: Mind's summary
/// and its week of blocks, the hub's rhythm, day changes and recommendations, in the shared container
/// (and in iCloud, which brings them back), and a profile either may have written last. None of that
/// may stop the stats reading, none of it is shown, and none of it is rewritten or deleted.
@Suite("What Stadig Mind and the hub left behind")
struct LegacyDataTests {
    let utc = TimeZone(identifier: "UTC")!
    let monday = Day(year: 2026, month: 11, day: 2)
    var now: Date { monday.at(hour: 10, minute: 0, timeZone: utc) }

    func container() throws -> (shared: SharedContainer, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (SharedContainer(directory: directory), directory)
    }

    /// A file as the app that's gone wrote it, by path: nothing here has a key for it any more.
    func writeRaw(_ json: String, to path: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
        return url
    }

    @Test func theStatsReadAroundMindsFiles() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        // The profile is shared, and Stadig Mind may have been the last to write it.
        let profile = SharedProfile(
            schedule: TrainingSchedule(daysPerWeek: 3, minutesPerSession: 60, preferredDays: [.monday, .wednesday, .friday]), recurring: [],
            createdBy: .knowledge)
        try shared.write(profile, to: .profile, by: .knowledge)
        let strength = StatReading(stat: .strength, score: 62, label: "Intermediate", trend: .onPace, updated: now)
        try shared.write(AppSummary(app: .liftTrack, updated: now, stats: [strength]), to: .summary(.liftTrack), by: .liftTrack)
        // Stadig Mind's own files: a summary with its stats and study sessions, and its week of blocks.
        let study = SessionSummary(
            id: UUID(), app: .knowledge, kind: .study, start: now, minutes: 25, statCredit: [.intelligence: 1, .wisdom: 0.5], planned: true)
        let mind = AppSummary(
            app: .knowledge, updated: now,
            stats: [
                StatReading(stat: .intelligence, score: 58, label: "Japanese and maths", trend: .onPace, updated: now),
                StatReading(stat: .wisdom, score: 66, label: "Reading", trend: .ahead, updated: now),
                StatReading(stat: .discipline, score: 90, label: "Study 90%", trend: .onPace, updated: now),
            ], sessions: [study])
        try shared.write(mind, to: .summary(.knowledge), by: .knowledge)
        let json =
            #"{"schemaVersion":1,"writtenBy":"knowledge","writtenAt":1793613600000,"payload":{"algorithm":1,"courses":[{"id":"japanese","blocks":4}]}}"#
        let blocks = try writeRaw(json, to: "apps/knowledge/blocks.json", in: directory)

        #expect(shared.read(.profile)?.schedule.daysPerWeek == 3, "a profile Stadig Mind wrote is still the profile")
        let lines = StatsBoard.lines(shared: shared, today: monday, timeZone: utc)
        #expect(lines.map(\.stat) == StatsBoard.shown)
        #expect(lines.filter(\.isKnown).map(\.stat) == [.strength], "Mind's Discipline isn't counted either")
        #expect(!StatsBoard.bothApps(shared: shared, today: monday, timeZone: utc))
        // And its files are left as they were, for the app that owns them.
        #expect(shared.read(.summary(.knowledge))?.stats.count == 3)
        #expect(try Data(contentsOf: blocks) == Data(json.utf8))
    }

    /// The hub's files are frozen at whatever it last wrote. No app reads them now, but they stay on
    /// disk and travel as before: backups and FamilySync carry every file by path.
    @Test func theHubsFilesAreLeftAsTheyAre() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rhythm = """
            {"schemaVersion":1,"writtenBy":"hub","writtenAt":1793613600000,"payload":{"wake":360,"bed":1350,"clearEvenings":2,"dayStart":4,\
            "placements":[{"title":"Muay Thai","weekday":7,"part":"midday"}],"updated":1793613600000}}
            """
        let changes = """
            {"schemaVersion":1,"writtenBy":"hub","writtenAt":1793613600000,"payload":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF",\
            "kind":"lighter","day":"2026-11-02","parts":[],"updatedAt":1793613600000}]}
            """
        let recommendations = """
            {"schemaVersion":1,"writtenBy":"hub","writtenAt":1793613600000,"payload":[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF",\
            "from":"hub","to":"liftTrack","kind":"deloadNow","reason":"Sleep has been short","created":1793613600000}]}
            """
        let files = [
            try writeRaw(rhythm, to: "hub/rhythm.json", in: directory), try writeRaw(changes, to: "hub/changes.json", in: directory),
            try writeRaw(recommendations, to: "hub/recommendations.json", in: directory),
        ]
        let before = try files.map { try Data(contentsOf: $0) }
        // A profile the hub last wrote still reads: `AppID.hub` stays a case for this.
        try shared.write(SharedProfile(createdBy: .hub), to: .profile, by: .hub)
        #expect(shared.read(.profile)?.createdBy == .hub)
        #expect(shared.envelope(.profile)?.writtenBy == .hub)

        // Both apps publishing around them, as they do on every change.
        let lift = AppSummary(
            app: .liftTrack, updated: now, stats: [StatReading(stat: .strength, score: 62, label: "Intermediate", trend: .onPace, updated: now)])
        let macro = AppSummary(
            app: .macroTrack, updated: now,
            stats: [StatReading(stat: .vitality, score: 86, label: "Logged 86% of days", trend: .onPace, updated: now)])
        try shared.write(lift, to: .summary(.liftTrack), by: .liftTrack)
        try shared.write(macro, to: .summary(.macroTrack), by: .macroTrack)
        try shared.write(SharedProfile(createdBy: .hub, updatedAt: now), to: .profile, by: .liftTrack)

        #expect(StatsBoard.bothApps(shared: shared, today: monday, timeZone: utc))
        #expect(StatsBoard.lines(shared: shared, today: monday, timeZone: utc).filter(\.isKnown).map(\.stat) == [.strength, .vitality])
        #expect(try files.map { try Data(contentsOf: $0) } == before)
        #expect(Set(shared.allFiles().keys).isSuperset(of: ["hub/rhythm.json", "hub/changes.json", "hub/recommendations.json"]))
    }
}
