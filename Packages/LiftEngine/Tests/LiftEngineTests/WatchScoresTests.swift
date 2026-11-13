import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// What the iPhone sends its Watch of the stats for the summary face: the scores the board has, how
/// far Strength moved this month, and the words for its next level, through the Watch's context.
@Suite("The scores the Watch shows")
struct WatchScoresTests {
    let today = Day(year: 2026, month: 11, day: 12)

    func summary(_ stats: [StatReading]) -> AppSummary {
        AppSummary(app: .liftTrack, updated: today.date(), stats: stats)
    }

    @Test("Each scored stat, and Strength's change this month, from the stats board")
    func fromTheBoard() throws {
        let history = ScoreHistory(app: .liftTrack, stats: [.strength: [ScorePoint(day: Day(year: 2026, month: 10, day: 20), score: 57)]])
        let lines = StatsBoard.lines(
            lift: summary([
                StatReading(stat: .strength, score: 58.2, label: "Novice", trend: .onPace),
                StatReading(stat: .endurance, score: 41, label: "Fair", trend: .onPace),
            ]), macro: nil, histories: [history], today: today)
        let scores = try #require(WatchScores(lines, strengthNext: "2 to Intermediate"))
        #expect(scores.strength == 58)
        #expect(scores.scores == [.strength: 58, .endurance: 41])
        #expect(scores.strengthChange?.short == "+1")
        #expect(scores.strengthNext == "2 to Intermediate")
    }

    @Test("Someone new, with nothing scored, sends none")
    func nothingScored() {
        let lines = StatsBoard.lines(lift: nil, macro: nil, today: today)
        #expect(WatchScores(lines) == nil)
    }

    @Test("They reach the Watch in its context, change and all, and an older phone's context has none")
    func throughTheContext() throws {
        let change = ScoreChange(
            points: 3.4, then: 55, from: Day(year: 2026, month: 8, day: 1), period: .since(month: Day(year: 2026, month: 8, day: 1), withYear: false))
        var context = PhoneContext(
            plan: nil, upNext: nil, gym: Gym.preset(.fullGym, unit: .kg), trust: TrustState(experience: .intermediate),
            phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: [:], enduranceScore: nil, heartRateGuidedRest: true,
            zones: HeartRateZones.estimated(age: 35, resting: 60), units: .regional)
        let older = try JSONEncoder().encode(context)
        #expect(try JSONDecoder().decode(PhoneContext.self, from: older).scores == nil)

        context.scores = WatchScores(scores: [.strength: 58, .vitality: 70], strengthChange: change, strengthNext: "2 to Intermediate")
        let decoded = try JSONDecoder().decode(PhoneContext.self, from: JSONEncoder().encode(context))
        #expect(decoded.scores == context.scores)
        #expect(decoded.scores?.strengthChange?.period == change.period)
    }
}
