import Foundation
import SystemCore
import Testing

@testable import HubEngine

@Suite("The stats page")
struct StatsBoardTests {
    let utc = TimeZone(identifier: "UTC")!
    let monday = Day(year: 2026, month: 11, day: 2)
    var now: Date { monday.at(hour: 10, minute: 0, timeZone: utc) }

    func inputs(lift: AppSummary? = nil, macro: AppSummary? = nil, mind: AppSummary? = nil) -> HubInputs {
        HubInputs(rhythm: Rhythm(), lift: lift, macro: macro, mind: mind, today: monday, now: now, timeZone: utc)
    }

    func reading(_ stat: StatKind, _ score: Double?, _ label: String, _ trend: Trajectory = .onPace) -> StatReading {
        StatReading(stat: stat, score: score, label: label, trend: trend, updated: now)
    }

    @Test func everyStatHasALineInTheSameOrder() {
        let lines = StatsBoard.lines(inputs())
        #expect(lines.map(\.stat) == StatKind.allCases)
        #expect(lines.filter(\.isKnown).isEmpty)
        #expect(lines.first?.label == "Nothing from Stadig Lift yet")
        #expect(lines.first { $0.stat == .wisdom }?.label == "Nothing from Stadig Mind yet")
    }

    @Test func oneAppSpeaksForAStat() throws {
        let lift = AppSummary(app: .liftTrack, updated: now, stats: [reading(.strength, 62.4, "Intermediate")])
        let line = try #require(StatsBoard.lines(inputs(lift: lift)).first)
        #expect(line.score == 62)
        #expect(line.label == "Intermediate")
        #expect(line.trend == .onPace)
        #expect(line.sources.map(\.app) == [.liftTrack])
    }

    /// There's no overall level, but a stat two apps publish is one stat.
    @Test func twoAppsShareDiscipline() throws {
        let lift = AppSummary(app: .liftTrack, updated: now, stats: [reading(.discipline, 84, "Training 84%", .onPace)])
        let macro = AppSummary(app: .macroTrack, updated: now, stats: [reading(.discipline, 92, "Nutrition 92%", .stalled)])
        let line = try #require(StatsBoard.lines(inputs(lift: lift, macro: macro)).first { $0.stat == .discipline })
        #expect(line.score == 88)
        #expect(line.label == "Training 84%, nutrition 92%")
        #expect(line.trend == .stalled)
        #expect(line.sources.map(\.score) == [84, 92])
    }

    @Test func aTrendThatKnowsBeatsOneThatDoesnt() {
        #expect(StatsBoard.worst([.notEnoughData, .ahead]) == .ahead)
        #expect(StatsBoard.worst([.notEnoughData]) == .notEnoughData)
        #expect(StatsBoard.worst([.ahead, .regressing]) == .regressing)
    }

    /// An app that's gone says nothing about now.
    @Test func staleSummariesCountForNothing() {
        let old = now.addingTimeInterval(-29 * 86_400)
        let lift = AppSummary(app: .liftTrack, updated: old, stats: [reading(.strength, 62, "Intermediate")])
        #expect(StatsBoard.lines(inputs(lift: lift)).filter(\.isKnown).isEmpty)
        #expect(StatsBoard.updated(inputs(lift: lift)) == nil)
    }

    @Test func updatedSaysWhen() {
        #expect(HubText.updated(nil, today: monday) == "Nothing from your apps yet")
        #expect(HubText.updated(monday.date(), today: monday) == "Updated today")
        #expect(HubText.updated(monday.date(), today: monday.adding(days: 1)) == "Updated yesterday")
        #expect(HubText.updated(monday.date(), today: monday.adding(days: 3)) == "Updated 3 days ago")
    }
}

@Suite("Moving a class")
struct MoveTests {
    let utc = TimeZone(identifier: "UTC")!
    /// A Monday.
    let monday = Day(year: 2026, month: 11, day: 2)
    var sunday: Day { monday.adding(days: 6) }
    var now: Date { monday.at(hour: 6, minute: 0, timeZone: utc) }

    var profile: SharedProfile {
        SharedProfile(
            schedule: TrainingSchedule(daysPerWeek: 2, minutesPerSession: 90, preferredDays: [.monday, .tuesday]),
            recurring: [RecurringActivity(activity: .muayThai, weekdays: [.wednesday, .sunday], minutes: 60)], createdBy: .liftTrack)
    }

    func inputs(placements: [ClassPlacement] = [], changes: [DayChange] = []) -> HubInputs {
        let rhythm = Rhythm(pattern: SchedulePreset.nothingFixed.pattern(anchor: monday), clearEvenings: 0, placements: placements)
        return HubInputs(
            rhythm: rhythm, changes: changes, profile: profile, lift: AppSummary(app: .liftTrack, updated: now), today: monday, now: now,
            timeZone: utc)
    }

    func thai(_ day: Day, _ inputs: HubInputs) -> HubItem? { HubPlanner.day(on: day, inputs).items.first { $0.title == "Muay Thai" } }

    let toMidday = ClassPlacement(title: "Muay Thai", weekday: .sunday, part: .midday)

    @Test func aClassStartsWhereStadigLiftSays() {
        #expect(thai(sunday, inputs())?.part == .evening)
    }

    @Test func everySundayMovesEverySundayAndNoOtherDay() {
        let inputs = inputs(placements: [toMidday])
        #expect(thai(sunday, inputs)?.part == .midday)
        #expect(thai(sunday.adding(weeks: 1), inputs)?.part == .midday)
        #expect(thai(monday.adding(days: 2), inputs)?.part == .evening)
    }

    @Test func justThisSundayLeavesTheNextOne() {
        let inputs = inputs(changes: [.move("Muay Thai", on: sunday, to: .midday, at: now)])
        #expect(thai(sunday, inputs)?.part == .midday)
        #expect(thai(sunday.adding(weeks: 1), inputs)?.part == .evening)
    }

    @Test func oneDayBeatsEveryWeek() {
        let inputs = inputs(placements: [toMidday], changes: [.move("Muay Thai", on: sunday, to: .morning, at: now)])
        #expect(thai(sunday, inputs)?.part == .morning)
    }

    @Test func undoneMovesStopCounting() {
        let undone = DayChange.move("Muay Thai", on: sunday, to: .midday, at: now).deleted(at: now)
        #expect(thai(sunday, inputs(changes: [undone]))?.part == .evening)
    }

    @Test func aMoveForAClassThatsGoneDoesNothing() {
        let inputs = inputs(placements: [ClassPlacement(title: "Boxing", weekday: .sunday, part: .midday)])
        #expect(thai(sunday, inputs)?.part == .evening)
    }

    @Test func theGymMovesToo() throws {
        let inputs = inputs(placements: [ClassPlacement(title: WeekCommitments.liftTitle, weekday: .monday, part: .early)])
        let gym = try #require(HubPlanner.day(on: monday, inputs).items.first { $0.kind == .lift })
        #expect(gym.part == .early)
        #expect(gym.canMove)
    }

    @Test func onlyClassesAndTheGymMove() {
        var meal = HubItem(id: "m", title: "Meal", kind: .meal, part: .midday, minutes: 30)
        #expect(!meal.canMove)
        meal.commitment = "Lift"
        meal.done = true
        #expect(!meal.canMove)
    }

    /// Study has to leave the part a class moved into, in every app, for just the day or for good.
    @Test func studyKeepsOutOfTheNewPart() throws {
        let rhythm = Rhythm(pattern: SchedulePreset.nothingFixed.pattern(anchor: monday), clearEvenings: 0, placements: [toMidday])
        let commitments = WeekCommitments(profile: profile, lift: nil, before: monday).placed(by: rhythm)
        let weekly = try #require(DayShape.studyParts(on: sunday, rhythm: rhythm, changes: [], commitments: commitments))
        #expect(!weekly.contains(.midday))
        #expect(weekly.contains(.evening))
        let change = DayChange.move("Muay Thai", on: sunday, to: .morning, at: now)
        let once = try #require(DayShape.studyParts(on: sunday, rhythm: rhythm, changes: [change], commitments: commitments))
        #expect(!once.contains(.morning))
        #expect(once.contains(.midday))
    }

    /// What Stadig Lift's Today says.
    @Test func aClassKnowsWhereItWent() throws {
        let item = try #require(profile.recurring.first)
        let rhythm = Rhythm(placements: [toMidday])
        #expect(item.part(on: sunday, rhythm: nil, changes: []) == .evening)
        #expect(item.part(on: sunday, rhythm: rhythm, changes: []) == .midday)
        #expect(item.part(on: sunday, rhythm: rhythm, changes: [.move("Muay Thai", on: sunday, to: .morning, at: now)]) == .morning)
    }

    /// Files from before moves: both payloads kept their schema, so these must read as they are.
    @Test func olderFilesStillRead() throws {
        let rhythm = #"{"wake":360,"bed":1350,"clearEvenings":2,"dayStart":4}"#
        let decoded = try JSONDecoder().decode(Rhythm.self, from: Data(rhythm.utf8))
        #expect(decoded.placements.isEmpty)
    }

    /// The other way round: an older build skips what it doesn't know.
    @Test func aMoveCantConfuseWhatClearsAnEvening() {
        let move = DayChange.move("Muay Thai", on: sunday, to: .evening, at: now)
        #expect([move].closedParts(on: sunday).isEmpty)
        #expect(![move].isLighter(sunday))
    }
}
