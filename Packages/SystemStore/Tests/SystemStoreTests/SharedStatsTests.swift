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

    /// Publishing records the day's scores in the app's own store, a record for the day saved only
    /// when its scores change; a new score the same day replaces the day's, the next day adds one.
    @Test @MainActor func publishingRecordsTheDaysScores() throws {
        let store = memoryStore()
        let recorded = store.recordScores(lift.stats, app: .liftTrack, on: monday, now: now)
        #expect(recorded.points(.strength) == [ScorePoint(day: monday, score: 62)])
        #expect(store.all(ScoreDayRecord.self).map(\.scores) == [[.strength: 62, .physique: 71, .endurance: 48, .agility: 54, .discipline: 84]])
        let revision = store.revision(of: ScoreDayRecord.self)
        #expect(store.recordScores(lift.stats, app: .liftTrack, on: monday, now: now.addingTimeInterval(60)) == recorded)
        #expect(store.revision(of: ScoreDayRecord.self) == revision, "nothing new, nothing saved")
        var stronger = lift.stats
        stronger[0].score = 63.04
        store.recordScores(stronger, app: .liftTrack, on: monday, now: now.addingTimeInterval(120))
        let history = store.recordScores(stronger, app: .liftTrack, on: monday.adding(days: 1), now: now.addingTimeInterval(86_400))
        #expect(history.points(.strength).map(\.score) == [63, 63])
        #expect(store.all(ScoreDayRecord.self).count == 2)
        #expect(history.points(.agility).map(\.day) == [monday, monday.adding(days: 1)])
    }

    /// Two devices record their own days, which the store carries one by one: the history is all of
    /// them. The same day from both is one record, the newer reading winning.
    @Test @MainActor func daysFromTwoDevicesAddUp() throws {
        let store = memoryStore()
        let phone = [ScoreDayRecord(day: monday.adding(days: -5), scores: [.strength: 55], updatedAt: now.addingTimeInterval(-5 * 86_400))]
        let pad = [
            ScoreDayRecord(day: monday.adding(days: -9), scores: [.strength: 50], updatedAt: now.addingTimeInterval(-9 * 86_400)),
            ScoreDayRecord(day: monday.adding(days: -5), scores: [.strength: 56], updatedAt: now.addingTimeInterval(-5 * 86_400 + 60)),
        ]
        #expect(phone[0].id == pad[1].id)
        store.save(phone)
        store.save(pad)
        let history = store.recordScores(lift.stats, app: .liftTrack, on: monday, now: now)
        #expect(
            history.points(.strength) == [
                ScorePoint(day: monday.adding(days: -9), score: 50), ScorePoint(day: monday.adding(days: -5), score: 56),
                ScorePoint(day: monday, score: 62),
            ])
        #expect(history.points(.strength).count == 3)
    }

    /// The store keeps every day; the history drawn from it thins what's past nine weeks.
    @Test @MainActor func theStoreKeepsEveryDayTheHistoryThins() throws {
        let store = memoryStore()
        store.save((1...120).map { back in ScoreDayRecord(day: monday.adding(days: -back), scores: [.strength: 50], updatedAt: now) })
        let history = store.recordScores(lift.stats, app: .liftTrack, on: monday, now: now)
        #expect(store.all(ScoreDayRecord.self).count == 121)
        #expect(history.points(.strength).count < 100)
        #expect(history.points(.strength).filter { $0.day.days(until: monday) <= ScoreHistory.dailyDays }.count == ScoreHistory.dailyDays + 1)
    }

    /// A day's record as the app's store keeps and syncs it: the day, an id from it, each stat's score.
    @Test func aDayRecordsStoredShape() throws {
        let json =
            #"{"day":"2026-11-02","id":"\#(ScoreDayRecord.id(for: monday).uuidString)","scores":{"discipline":84,"strength":62.4},"updatedAt":1793613600000}"#
        let record = try SystemJSON.decoder().decode(ScoreDayRecord.self, from: Data(json.utf8))
        #expect(
            record == ScoreDayRecord(day: monday, scores: [.strength: 62.4, .discipline: 84], updatedAt: Date(timeIntervalSince1970: 1_793_613_600)))
        #expect(String(decoding: try SystemJSON.encoder().encode(record), as: UTF8.self) == json)
        #expect(ScoreDayRecord.kind == "score-day")
        #expect(ScoreDayRecord.schemaVersion == 1)
        #expect(ScoreDayRecord.id(for: monday) != ScoreDayRecord.id(for: monday.adding(days: 1)))
    }

    /// Both apps read each other's histories from the container: a line says how far it moved this
    /// month, and Discipline by the average of both apps' changes.
    @Test @MainActor func linesFromTheContainerSayHowFarEachMoved() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        let monthAgo = monday.adding(days: -31)
        try shared.write(lift, to: .summary(.liftTrack), by: .liftTrack)
        try shared.write(macro, to: .summary(.macroTrack), by: .macroTrack)
        let liftDays = memoryStore()
        liftDays.recordScores(
            [reading(.strength, 60, ""), reading(.endurance, 48.4, ""), reading(.discipline, 80, "")], app: .liftTrack, on: monthAgo, now: now)
        try shared.write(liftDays.recordScores(lift.stats, app: .liftTrack, on: monday, now: now), to: .scores(.liftTrack), by: .liftTrack)
        let macroDays = memoryStore()
        macroDays.recordScores([reading(.vitality, 87, ""), reading(.discipline, 90, "")], app: .macroTrack, on: monthAgo, now: now)
        try shared.write(macroDays.recordScores(macro.stats, app: .macroTrack, on: monday, now: now), to: .scores(.macroTrack), by: .macroTrack)
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
    @Test @MainActor func anAppThatRecordsNoHistoryShowsNoChange() throws {
        let (shared, directory) = try container()
        defer { try? FileManager.default.removeItem(at: directory) }
        try shared.write(lift, to: .summary(.liftTrack), by: .liftTrack)
        try shared.write(macro, to: .summary(.macroTrack), by: .macroTrack)
        let macroDays = memoryStore()
        macroDays.recordScores([reading(.vitality, 80, "")], app: .macroTrack, on: monday.adding(days: -31), now: now)
        try shared.write(macroDays.recordScores(macro.stats, app: .macroTrack, on: monday, now: now), to: .scores(.macroTrack), by: .macroTrack)
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
        #expect(throws: SystemStoreError.self) { try shared.write(ScoreHistory(app: .liftTrack), to: .scores(.liftTrack), by: .liftTrack) }
        #expect(shared.envelope(newer)?.schemaVersion == ScoreHistory.schemaVersion + 1)
    }
}
