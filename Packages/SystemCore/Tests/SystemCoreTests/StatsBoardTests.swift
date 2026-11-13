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

    // MARK: How each has moved

    func history(_ app: AppID, _ stats: [StatKind: [(back: Int, score: Double)]]) -> ScoreHistory {
        ScoreHistory(app: app, stats: stats.mapValues { $0.map { ScorePoint(day: monday.adding(days: -$0.back), score: $0.score) } })
    }

    /// Each line carries how far it moved this month, from the histories the apps recorded; a stat
    /// with nothing recorded, or only today, has none.
    @Test func linesSayHowFarEachMovedThisMonth() throws {
        let lift = AppSummary(
            app: .liftTrack, updated: now,
            stats: [reading(.strength, 57.2, "Novice"), reading(.agility, 61.3, "Mobile"), reading(.physique, 64, "Proportions")])
        let recorded = history(.liftTrack, [.strength: [(40, 50), (31, 55), (0, 57.2)], .agility: [(31, 61), (0, 61.3)], .physique: [(0, 64)]])
        let lines = StatsBoard.lines(lift: lift, macro: nil, histories: [recorded], today: monday, timeZone: utc)
        let strength = try #require(lines.first { $0.stat == .strength })
        #expect(strength.change?.short == "+2")
        #expect(strength.change?.from == monday.adding(days: -31))
        #expect(lines.first { $0.stat == .agility }?.change?.short == "steady")
        #expect(lines.first { $0.stat == .physique }?.change == nil, "only today's reading")
        #expect(lines.first { $0.stat == .endurance }?.change == nil, "nothing published")
        // Without histories, as from an app that records none, no line has a change.
        #expect(self.lines(lift: lift).allSatisfy { $0.change == nil })
        // Another app's history doesn't speak for this one's stats.
        let wrongApp = StatsBoard.lines(
            lift: lift, macro: nil, histories: [history(.macroTrack, [.strength: [(31, 40)]])], today: monday, timeZone: utc)
        #expect(wrongApp.allSatisfy { $0.change == nil })
    }

    /// Discipline from both apps moves by the average of their changes.
    @Test func sharedDisciplineMovesByBothApps() throws {
        let lift = AppSummary(app: .liftTrack, updated: now, stats: [reading(.discipline, 88, "Training 88%")])
        let macro = AppSummary(app: .macroTrack, updated: now, stats: [reading(.discipline, 84, "Nutrition 84%")])
        let lines = StatsBoard.lines(
            lift: lift, macro: macro,
            histories: [history(.liftTrack, [.discipline: [(35, 82)]]), history(.macroTrack, [.discipline: [(35, 82)]])],
            today: monday, timeZone: utc)
        let discipline = try #require(lines.first { $0.stat == .discipline })
        #expect(discipline.score == 86)
        #expect(discipline.change?.points == 4)
        #expect(discipline.change?.then == 82)
    }

    /// Your shape's dashed outline: the scores as August began, named August; a score first recorded
    /// in October has no corner on it. Readings from this month only draw none.
    @Test func theOutlineIsTheShapeAMonthNamed() throws {
        let today = Day(year: 2026, month: 11, day: 11)
        let at = today.at(hour: 10, minute: 0, timeZone: utc)
        let lift = AppSummary(
            app: .liftTrack, updated: at,
            stats: [
                StatReading(stat: .strength, score: 57, label: "", trend: .onPace, updated: at),
                StatReading(stat: .endurance, score: 48, label: "", trend: .onPace, updated: at),
            ])
        let macro = AppSummary(
            app: .macroTrack, updated: at, stats: [StatReading(stat: .vitality, score: 72, label: "", trend: .onPace, updated: at)])
        let july = Day(year: 2026, month: 7, day: 31)
        let histories = [
            ScoreHistory(app: .liftTrack, stats: [.strength: [ScorePoint(day: july, score: 52.4)], .endurance: [ScorePoint(day: july, score: 45)]]),
            ScoreHistory(app: .macroTrack, stats: [.vitality: [ScorePoint(day: Day(year: 2026, month: 10, day: 2), score: 73)]]),
        ]
        let lines = StatsBoard.lines(lift: lift, macro: macro, histories: histories, today: today, timeZone: utc)
        let earlier = try #require(StatsBoard.earlier(lines, today: today))
        #expect(earlier.period == .since(month: Day(year: 2026, month: 8, day: 1), withYear: false))
        #expect(earlier.period.monthName(calendar: Calendar(identifier: .gregorian)) != nil)
        #expect(earlier.scores == [.strength: 52, .endurance: 45])
        #expect(
            lines.first { $0.stat == .vitality }?.change(over: StatsBoard.lookBack(today: today), today: today)?.period
                == .since(month: Day(year: 2026, month: 10, day: 1), withYear: false))

        let recent = [ScoreHistory(app: .liftTrack, stats: [.strength: [ScorePoint(day: Day(year: 2026, month: 11, day: 2), score: 55)]])]
        #expect(StatsBoard.earlier(StatsBoard.lines(lift: lift, macro: nil, histories: recent, today: today, timeZone: utc), today: today) == nil)
        #expect(StatsBoard.earlier(StatsBoard.lines(lift: lift, macro: nil, today: today, timeZone: utc), today: today) == nil)
    }
}
