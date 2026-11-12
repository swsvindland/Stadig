import Foundation
import Testing

@testable import SystemCore

/// The six fitness stats merged from summaries in hand, as both apps show them.
@Suite("The stats board")
struct StatsBoardTests {
    let utc = TimeZone(identifier: "UTC")!
    let monday = Day(year: 2026, month: 11, day: 2)
    var now: Date { monday.at(hour: 10, minute: 0, timeZone: utc) }

    func lines(lift: AppSummary? = nil, macro: AppSummary? = nil) -> [StatLine] {
        StatsBoard.lines(lift: lift, macro: macro, today: monday, timeZone: utc)
    }

    func reading(_ stat: StatKind, _ score: Double?, _ label: String, _ trend: Trajectory = .onPace) -> StatReading {
        StatReading(stat: stat, score: score, label: label, trend: trend, updated: now)
    }

    @Test func everyStatHasALineInTheSameOrder() {
        let lines = lines()
        #expect(lines.map(\.stat) == [.strength, .physique, .endurance, .vitality, .agility, .discipline])
        #expect(lines.filter(\.isKnown).isEmpty)
        #expect(lines.first?.label == "Nothing from Stadig Lift yet")
        #expect(lines.first { $0.stat == .vitality }?.label == "Nothing from Stadig Macro yet")
    }

    /// Only fitness is scored. A summary that still carries Stadig Mind's stats (an old file, or a
    /// stat credited by mistake) adds no line for them.
    @Test func intelligenceAndWisdomAreNeverShown() {
        let lift = AppSummary(
            app: .liftTrack, updated: now,
            stats: [reading(.strength, 62, "Intermediate"), reading(.wisdom, 60, "Reading"), reading(.intelligence, 58, "Maths")])
        let lines = lines(lift: lift)
        #expect(lines.filter(\.isKnown).map(\.stat) == [.strength])
        #expect(!lines.contains { $0.stat == .wisdom || $0.stat == .intelligence })
    }

    @Test func oneAppSpeaksForAStat() throws {
        let lift = AppSummary(app: .liftTrack, updated: now, stats: [reading(.strength, 62.4, "Intermediate")])
        let line = try #require(lines(lift: lift).first)
        #expect(line.score == 62)
        #expect(line.label == "Intermediate")
        #expect(line.trend == .onPace)
        #expect(line.sources.map(\.app) == [.liftTrack])
    }

    /// There's no overall level, but a stat two apps publish is one stat.
    @Test func twoAppsShareDiscipline() throws {
        let lift = AppSummary(app: .liftTrack, updated: now, stats: [reading(.discipline, 84, "Training 84%", .onPace)])
        let macro = AppSummary(app: .macroTrack, updated: now, stats: [reading(.discipline, 92, "Nutrition 92%", .stalled)])
        let line = try #require(lines(lift: lift, macro: macro).first { $0.stat == .discipline })
        #expect(line.score == 88)
        #expect(line.label == "Training 84%, nutrition 92%")
        #expect(line.trend == .stalled)
        #expect(line.sources.map(\.score) == [84, 92])
        #expect(StatsBoard.bothApps(lift: lift, macro: macro, today: monday, timeZone: utc))
    }

    @Test func aTrendThatKnowsBeatsOneThatDoesnt() {
        #expect(StatsBoard.worst([.notEnoughData, .ahead]) == .ahead)
        #expect(StatsBoard.worst([.notEnoughData]) == .notEnoughData)
        #expect(StatsBoard.worst([.ahead, .regressing]) == .regressing)
    }

    /// An app that's gone says nothing about now: four weeks is the most a summary counts for.
    @Test func staleSummariesCountForNothing() {
        let lift = AppSummary(app: .liftTrack, updated: now.addingTimeInterval(-29 * 86_400), stats: [reading(.strength, 62, "Intermediate")])
        #expect(lines(lift: lift).filter(\.isKnown).isEmpty)
        let edge = AppSummary(app: .liftTrack, updated: now.addingTimeInterval(-28 * 86_400), stats: [reading(.strength, 62, "Intermediate")])
        #expect(lines(lift: edge).filter(\.isKnown).map(\.stat) == [.strength])
    }
}
