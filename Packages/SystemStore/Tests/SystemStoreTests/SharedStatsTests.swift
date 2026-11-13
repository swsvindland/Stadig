import Foundation
import SystemCore
import Testing

@testable import SystemStore

/// What either app calls for its stats: the six fitness stats merged from what Stadig Lift and Stadig
/// Macro publish to the shared container, each saying which app it comes from.
@Suite("The stats each app shows")
struct SharedStatsTests {
    let utc = TimeZone(identifier: "UTC")!
    let monday = Day(year: 2026, month: 11, day: 2)
    var now: Date { monday.at(hour: 10, minute: 0, timeZone: utc) }

    func container() throws -> (shared: SharedContainer, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("stats-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (SharedContainer(directory: directory), directory)
    }

    func reading(_ stat: StatKind, _ score: Double?, _ label: String, _ trend: Trajectory = .onPace) -> StatReading {
        StatReading(stat: stat, score: score, label: label, trend: trend, updated: now)
    }

    var lift: AppSummary {
        AppSummary(
            app: .liftTrack, updated: now,
            stats: [
                reading(.strength, 62, "Intermediate"), reading(.physique, 71, "Proportions"), reading(.endurance, 48, "Engine"),
                reading(.agility, 54, "Limiter: Hips"), reading(.discipline, 84, "Training 84%"),
            ])
    }

    var macro: AppSummary {
        AppSummary(
            app: .macroTrack, updated: now,
            stats: [reading(.vitality, 86, "Logged 86% of days"), reading(.discipline, 92, "Nutrition 92%", .stalled)])
    }

    @Test func withNothingPublishedEveryStatSaysWhichAppWouldDecideIt() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lines = StatsBoard.lines(shared: shared, today: monday, timeZone: utc)
        #expect(lines.map(\.stat) == [.strength, .physique, .endurance, .vitality, .agility, .discipline])
        #expect(lines.allSatisfy { !$0.isKnown && $0.apps.isEmpty && $0.score == nil })
        #expect(lines.map(\.app) == [.liftTrack, .liftTrack, .liftTrack, .macroTrack, .liftTrack, .liftTrack])
        #expect(!StatsBoard.bothApps(shared: shared, today: monday, timeZone: utc))
    }

    @Test func oneAppAloneShowsItsOwn() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        try shared.write(macro, to: .summary(.macroTrack), by: .macroTrack)
        let known = StatsBoard.lines(shared: shared, today: monday, timeZone: utc).filter(\.isKnown)
        #expect(known.map(\.stat) == [.vitality, .discipline])
        #expect(known.allSatisfy { $0.apps == [.macroTrack] })
        #expect(known.last?.score == 92)
        #expect(!StatsBoard.bothApps(shared: shared, today: monday, timeZone: utc))
    }

    @Test func bothAppsShowEveryStatWithTheAppThatDecidesIt() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        try shared.write(lift, to: .summary(.liftTrack), by: .liftTrack)
        try shared.write(macro, to: .summary(.macroTrack), by: .macroTrack)
        let lines = StatsBoard.lines(shared: shared, today: monday, timeZone: utc)
        #expect(StatsBoard.bothApps(shared: shared, today: monday, timeZone: utc))
        #expect(lines.allSatisfy { $0.isKnown })
        let apps = Dictionary(uniqueKeysWithValues: lines.map { ($0.stat, $0.apps) })
        #expect(apps[.strength] == [.liftTrack])
        #expect(apps[.physique] == [.liftTrack])
        #expect(apps[.endurance] == [.liftTrack])
        #expect(apps[.agility] == [.liftTrack])
        #expect(apps[.vitality] == [.macroTrack])
        #expect(apps[.discipline] == [.liftTrack, .macroTrack], "the one stat both decide")
        let discipline = try #require(lines.first { $0.stat == .discipline })
        #expect(discipline.score == 88)
        #expect(discipline.sources.map(\.score) == [84, 92])
        #expect(discipline.trend == .stalled)
        // The same answer from summaries in hand, which is how an app passes its own before it's written.
        #expect(StatsBoard.lines(lift: lift, macro: macro, today: monday, timeZone: utc) == lines)
    }

    /// Four weeks unopened and an app's numbers say nothing about now.
    @Test func anAppThatsGoneQuietDropsOut() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        var old = macro
        old.updated = now.addingTimeInterval(-29 * 86_400)
        try shared.write(lift, to: .summary(.liftTrack), by: .liftTrack)
        try shared.write(old, to: .summary(.macroTrack), by: .macroTrack)
        let lines = StatsBoard.lines(shared: shared, today: monday, timeZone: utc)
        #expect(lines.first { $0.stat == .vitality }?.isKnown == false)
        #expect(lines.first { $0.stat == .discipline }?.apps == [.liftTrack])
        #expect(!StatsBoard.bothApps(shared: shared, today: monday, timeZone: utc))
    }

    /// Only the two fitness apps count, whatever is handed in.
    @Test func aSummaryFromAnotherAppIsIgnored() {
        let mind = AppSummary(app: .knowledge, updated: now, stats: [reading(.discipline, 90, "Study 90%"), reading(.wisdom, 66, "Reading")])
        let lines = StatsBoard.lines(lift: mind, macro: macro, today: monday, timeZone: utc)
        #expect(lines.first { $0.stat == .discipline }?.apps == [.macroTrack])
        #expect(!lines.contains { $0.stat == .wisdom })
    }

    // MARK: How each has moved

    /// Publishing records the day's scores in the app's own file beside its summary; publishing the
    /// same again writes nothing, so the other app isn't woken for it.
    @Test func publishingRecordsTheDaysScores() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorded = try shared.recordScores(lift.stats, by: .liftTrack, on: monday)
        #expect(shared.read(.scores(.liftTrack)) == recorded)
        #expect(recorded.points(.strength) == [ScorePoint(day: monday, score: 62)])
        let written = try #require(shared.envelope(.scores(.liftTrack))?.writtenAt)
        try shared.recordScores(lift.stats, by: .liftTrack, on: monday, kept: recorded)
        #expect(shared.envelope(.scores(.liftTrack))?.writtenAt == written)
        // A new score the same day replaces the day's; the next day adds one.
        var stronger = lift.stats
        stronger[0].score = 63.04
        try shared.recordScores(stronger, by: .liftTrack, on: monday)
        try shared.recordScores(stronger, by: .liftTrack, on: monday.adding(days: 1))
        #expect(shared.read(.scores(.liftTrack))?.points(.strength).map(\.score) == [63, 63])
    }

    /// The phone recorded days the iPad's copy, newer and brought by iCloud, never had: recording
    /// over the file with what the phone kept brings them back for both.
    @Test func daysAnotherDevicesCopyLackedComeBack() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        var phone = ScoreHistory(app: .liftTrack)
        for back in (1...5).reversed() { phone = phone.recording([reading(.strength, 60 - Double(back), "")], on: monday.adding(days: -back)) }
        let pad = ScoreHistory(app: .liftTrack).recording([reading(.strength, 50, "")], on: monday.adding(days: -9))
            .recording([reading(.strength, 58.5, "")], on: monday.adding(days: -2))
        try shared.write(pad, to: .scores(.liftTrack), by: .liftTrack)
        let merged = try shared.recordScores(lift.stats, by: .liftTrack, on: monday, kept: phone)
        #expect(merged.points(.strength).map(\.day) == [9, 5, 4, 3, 2, 1, 0].map { monday.adding(days: -$0) })
        #expect(merged.points(.strength).first { $0.day == monday.adding(days: -2) }?.score == 58.5, "the file's copy of a day both have")
        #expect(shared.read(.scores(.liftTrack)) == merged)
    }

    /// Both apps read each other's histories from the container: a line says how far it moved this
    /// month, and Discipline by the average of both apps' changes.
    @Test func linesFromTheContainerSayHowFarEachMoved() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let monthAgo = monday.adding(days: -31)
        try shared.write(lift, to: .summary(.liftTrack), by: .liftTrack)
        try shared.write(macro, to: .summary(.macroTrack), by: .macroTrack)
        try shared.recordScores(
            [reading(.strength, 60, ""), reading(.endurance, 48.4, ""), reading(.discipline, 80, "")], by: .liftTrack, on: monthAgo)
        try shared.recordScores([reading(.vitality, 87, ""), reading(.discipline, 90, "")], by: .macroTrack, on: monthAgo)
        let lines = StatsBoard.lines(shared: shared, today: monday, timeZone: utc)
        let changes = Dictionary(uniqueKeysWithValues: lines.map { ($0.stat, $0.change?.short) })
        #expect(changes[.strength] == "+2")
        #expect(changes[.endurance] == "steady")
        #expect(changes[.vitality] == "\u{2212}1")
        #expect(changes[.discipline] == "+3", "Lift +4, Macro +2")
        #expect(changes[.physique] == .some(nil), "nothing recorded a month ago")
    }

    /// An older copy of an app publishes its summary but no history: its scores show as before,
    /// with no change, and the other app's still have theirs.
    @Test func anAppThatRecordsNoHistoryShowsNoChange() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        try shared.write(lift, to: .summary(.liftTrack), by: .liftTrack)
        try shared.write(macro, to: .summary(.macroTrack), by: .macroTrack)
        try shared.recordScores([reading(.vitality, 80, "")], by: .macroTrack, on: monday.adding(days: -31))
        let lines = StatsBoard.lines(shared: shared, today: monday, timeZone: utc)
        #expect(lines.first { $0.stat == .strength }?.score == 62)
        #expect(lines.filter { $0.change != nil }.map(\.stat) == [.vitality])
    }

    /// A history written by a newer version is left alone, as every shared file is.
    @Test func aNewerHistoryIsNeverOverwritten() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let newer = SharedKey<ScoreHistory>(path: "apps/liftTrack/scores.json", schemaVersion: ScoreHistory.schemaVersion + 1)
        try shared.write(ScoreHistory(app: .liftTrack), to: newer, by: .liftTrack)
        #expect(shared.read(.scores(.liftTrack)) == nil)
        #expect(throws: SystemStoreError.self) { try shared.recordScores(lift.stats, by: .liftTrack, on: monday) }
        #expect(shared.envelope(newer)?.schemaVersion == ScoreHistory.schemaVersion + 1)
    }
}
