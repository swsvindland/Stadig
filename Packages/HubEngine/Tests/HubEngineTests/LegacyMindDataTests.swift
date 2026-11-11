import Foundation
import SystemCore
import SystemStore
import Testing

@testable import HubEngine

/// Stadig Mind left the family, but devices still hold what it published: its summary and its week of
/// blocks in the shared container (and in iCloud, which brings them back), a profile it last wrote,
/// life modes it made. None of that may stop the fitness side reading, and none of it is shown.
@Suite("What Stadig Mind left behind")
struct LegacyMindDataTests {
    let utc = TimeZone(identifier: "UTC")!
    let monday = Day(year: 2026, month: 11, day: 2)
    var now: Date { monday.at(hour: 10, minute: 0, timeZone: utc) }

    func container() throws -> (shared: SharedContainer, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hub-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (SharedContainer(directory: directory), directory)
    }

    @Test func theHubReadsFitnessAroundMindsFiles() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        try shared.write(Rhythm(pattern: SchedulePreset.nineToFive.pattern(anchor: monday)), to: .rhythm, by: .hub)
        // The profile is shared, and Stadig Mind may have been the last to write it.
        let profile = SharedProfile(
            schedule: TrainingSchedule(daysPerWeek: 3, minutesPerSession: 60, preferredDays: [.monday, .wednesday, .friday]), recurring: [],
            createdBy: .knowledge)
        try shared.write(profile, to: .profile, by: .knowledge)
        let strength = StatReading(stat: .strength, score: 62, label: "Intermediate", trend: .onPace, updated: now)
        try shared.write(AppSummary(app: .liftTrack, updated: now, stats: [strength]), to: .summary(.liftTrack), by: .liftTrack)
        try shared.write(MealRhythm(usual: [.morning, .evening], day: monday, eaten: [], updated: now), to: .mealRhythm, by: .macroTrack)
        // Stadig Mind's own files: a summary with its stats and study sessions, and its week of blocks,
        // which nothing here has a key for any more.
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
        let blocks = directory.appendingPathComponent("apps/knowledge/blocks.json")
        let json =
            #"{"schemaVersion":1,"writtenBy":"knowledge","writtenAt":1793613600000,"payload":{"algorithm":1,"courses":[{"id":"japanese","blocks":4}]}}"#
        try Data(json.utf8).write(to: blocks)

        let inputs = try #require(HubInputs(shared: shared, today: monday, now: now, timeZone: utc))
        #expect(inputs.profile?.schedule.daysPerWeek == 3, "a profile Stadig Mind wrote is still the profile")
        let lines = StatsBoard.lines(inputs)
        #expect(lines.map(\.stat) == StatsBoard.shown)
        #expect(lines.filter(\.isKnown).map(\.stat) == [.strength], "Mind's Discipline isn't counted either")
        let week = HubPlanner.week(of: monday, inputs)
        #expect(week.gym == 3)
        #expect(Set(week.days.flatMap(\.items).map(\.kind)) == [.work, .lift, .meal])
        #expect(RhythmSummary.lines(inputs).map(\.label) == ["Gym", "Meals"])
        // And its files are left as they were, for the app that owns them.
        #expect(shared.read(.summary(.knowledge))?.stats.count == 3)
        #expect(try Data(contentsOf: blocks) == Data(json.utf8))
    }
}
