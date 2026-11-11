import Foundation
import SystemCore
import SystemStore
import Testing

@testable import HubEngine

/// What either app calls for its stats: the six fitness stats merged from what Stadig Lift and Stadig
/// Macro publish, each saying which app it comes from. No hub and no rhythm needed.
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
}
