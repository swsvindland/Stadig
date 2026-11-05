import Foundation
import SystemCore
import Testing

@testable import MindEngine

@Suite("Week settings")
struct WeekSettingsTests {
    let day = Day(year: 2026, month: 11, day: 2)
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func tiersSeedBlocks() {
        let settings = MindSettings(courses: [.japanese: .focus, .reading: .focus, .maths: .secondary, .writing: .maintenance])
        let week = WeekSettings.seeded(from: settings, since: day, now: now)
        #expect(week.blocks(.japanese) == 4)
        #expect(week.blocks(.reading) == 4)
        #expect(week.blocks(.maths) == 2)
        #expect(week.blocks(.writing) == 0)
        #expect(week.since == day)
    }

    /// The old default, all four courses on Main, would otherwise become 16 blocks: four times the
    /// hours it was.
    @Test func seedsStopAtTheCapTakingFromNonLanguagesFirst() {
        let week = WeekSettings.seeded(from: MindSettings(), since: day, now: now)
        #expect(week.total(Domain.allCases) == WeekSettings.seedCap)
        #expect(week.blocks(.japanese) == 4)
        #expect(week.blocks(.maths) == 2)
        #expect(week.blocks(.writing) == 2)
        #expect(week.blocks(.reading) == 2)
    }

    @Test func trimmingNeverTakesACourseToNothing() {
        let trimmed = WeekSettings.trimmed([.japanese: 7, .spanish: 7, .maths: 7, .writing: 7, .reading: 7])
        #expect(trimmed.values.reduce(0, +) == WeekSettings.seedCap)
        #expect(trimmed.values.allSatisfy { $0 >= 1 })
        #expect(trimmed[.japanese, default: 0] + trimmed[.spanish, default: 0] == 7)
    }

    @Test func newPeopleStartWithLanguagesMost() {
        let week = WeekSettings.fresh([.japanese, .reading, .maths, .writing], since: day, now: now)
        #expect(week.blocks(.japanese) == 4)
        #expect(week.blocks(.reading) == 3)
        #expect(week.blocks(.maths) == 2)
        #expect(week.blocks(.writing) == 1)
    }

    @Test func blocksStayInRange() {
        var week = WeekSettings(since: day)
        week.setBlocks(40, for: .maths)
        #expect(week.blocks(.maths) == 7)
        week.setBlocks(-1, for: .maths)
        #expect(week.blocks(.maths) == 0)
    }

    @Test func aPartLeftAloneHasNoOverride() {
        var week = WeekSettings(since: day)
        #expect(week.override(.monday, .evening) == nil)
        week.setOverride(true, .monday, .evening)
        #expect(week.override(.monday, .evening) == true)
        #expect(week.override(.tuesday, .evening) == nil)
        week.setOverride(nil, .monday, .evening)
        #expect(week.parts.isEmpty)
    }

    @Test func pinsRoundTrip() {
        var week = WeekSettings(since: day)
        week.setPin(.morning, for: .maths)
        #expect(week.pin(.maths) == .morning)
        week.setPin(nil, for: .maths)
        #expect(week.pin(.maths) == nil)
    }

    @Test func oldTargetsAreForgotten() {
        var week = WeekSettings(since: day)
        func target(_ total: Int) -> WeekTarget { WeekTarget(total: total, counts: [.japanese: total], days: 7) }
        week.record(target(10), for: day)
        week.record(target(11), for: day.adding(weeks: 6))
        #expect(week.target(day)?.total == 10)
        week.record(target(12), for: day.adding(weeks: 7))
        #expect(week.target(day) == nil)
        #expect(week.target(day.adding(weeks: 7))?.total == 12)
    }

    @Test func aCourseFromANewerBuildSurvives() throws {
        let json = #"{"blocks":{"piano":3,"maths":2},"since":"2026-11-02"}"#
        var week = try JSONDecoder().decode(WeekSettings.self, from: Data(json.utf8))
        #expect(week.blocks(.maths) == 2)
        week.setBlocks(3, for: .maths)
        let again = try JSONDecoder().decode(WeekSettings.self, from: JSONEncoder().encode(week))
        #expect(again.blocks["piano"] == 3)
        #expect(again.blocks(.maths) == 3)
    }

    @Test func tiersForOlderBuildsFollowTheBlocks() {
        let week = WeekSettings(blocks: [.japanese: 4, .reading: 2, .maths: 0], since: day)
        let modes = week.modes([.japanese, .reading, .maths])
        #expect(modes == [.japanese: .focus, .reading: .secondary, .maths: .maintenance])
    }

    /// An older build has nothing to put in its split without a Main course.
    @Test func theBiggestCourseStaysMainForOlderBuilds() {
        let week = WeekSettings(blocks: [.japanese: 2, .reading: 1], since: day)
        #expect(week.modes([.japanese, .reading]) == [.japanese: .focus, .reading: .secondary])
    }

    @Test func anAmountIsOffReviewsOnlyOrBlocks() {
        var settings = MindSettings(courses: [.japanese: .focus, .maths: .focus])
        var week = WeekSettings(blocks: [.japanese: 4, .maths: 2], since: day)
        #expect(week.amount(.japanese, settings: settings) == 4)
        #expect(week.amount(.writing, settings: settings) == WeekSettings.courseOff)
        #expect(week.setAmount(0, for: .maths, settings: &settings))
        #expect(settings.mode(.maths) == .maintenance)
        #expect(week.setAmount(2, for: .writing, settings: &settings))
        #expect(settings.mode(.writing) == .secondary)
        #expect(week.setAmount(WeekSettings.courseOff, for: .writing, settings: &settings))
        #expect(!settings.has(.writing))
        #expect(WeekSettings.amountLabel(-1) == "Off")
        #expect(WeekSettings.amountLabel(0) == "Reviews only")
        #expect(WeekSettings.amountLabel(4) == "4 a week")
    }

    /// With nothing to plan, the week would be empty: at least one course keeps its blocks.
    @Test func theLastCourseWithBlocksStays() {
        var settings = MindSettings(courses: [.japanese: .focus, .maths: .maintenance])
        var week = WeekSettings(blocks: [.japanese: 4], since: day)
        #expect(!week.setAmount(0, for: .japanese, settings: &settings))
        #expect(!week.setAmount(WeekSettings.courseOff, for: .japanese, settings: &settings))
        #expect(week.blocks(.japanese) == 4)
        #expect(settings.has(.japanese))
    }

    @Test func tooManyBlocksGetAWarning() {
        let settings = MindSettings(courses: [.japanese: .focus, .reading: .focus])
        var week = WeekSettings(blocks: [.japanese: 7, .reading: 7], since: day)
        for weekday in Weekday.allCases { for part in DayPart.allCases { week.setOverride(weekday == .monday, weekday, part) } }
        let warning = CourseLoad.warning(settings, week: week, commitments: .none)
        #expect(warning == "14 blocks and 6 open parts of the week. Open a part, or drop a block.")
    }

    @Test func aThinLanguageGetsAWarning() {
        let settings = MindSettings(courses: [.japanese: .focus, .reading: .focus])
        let week = WeekSettings(blocks: [.japanese: 1, .reading: 4], since: day)
        #expect(CourseLoad.warning(settings, week: week, commitments: .none)?.hasPrefix("Japanese on one block") == true)
    }
}
