import Foundation
import SystemCore
import Testing

@testable import MindEngine

/// Days start at 4 a.m. unless the person changes it: a lesson done after midnight, before bed,
/// is the evening's, not the next day's.
@Suite("When the day starts")
struct DayStartTests {
    /// Friday and Saturday are both study days in the five-day split.
    let friday = Fixtures.monday.adding(days: 18)
    var saturday: Day { friday.adding(days: 1) }

    func settings(dayStart: Int) -> MindSettings {
        var settings = Fixtures.settings()
        settings.dayStart = dayStart
        return settings
    }

    /// Friday's session, started at half past midnight on Saturday.
    var lateSession: StudySession {
        let start = saturday.at(hour: 0, minute: 30)
        return StudySession(
            purpose: .regular, start: start, end: start + 1500, plannedMinutes: 25, domains: [.japanese], planned: true,
            activeSeconds: 1500, ranToEnd: true)
    }

    func state(dayStart: Int, now: Date) -> StudyState {
        StudyState(settings: settings(dayStart: dayStart), sessions: [lateSession], today: Day(now, dayStartsAt: dayStart), now: now)
    }

    /// The days a state's finished blocks count for.
    func blockDays(_ state: StudyState) -> [Day] {
        WeekPlanner.finished(state, settings: state.week, monday: state.today.startOfWeek, timeZone: .current).map(\.day)
    }

    @Test("a session after midnight counts for the evening before, and the next day's still waits")
    func lateSessionIsTheEvenings() {
        #expect(settings(dayStart: 4).schedule.studyDays.contains(friday.weekday))
        #expect(settings(dayStart: 4).schedule.studyDays.contains(saturday.weekday))
        // Just after it, the day hasn't turned over yet: it's still Friday, and Friday's done.
        let late = state(dayStart: 4, now: saturday.at(hour: 0, minute: 58))
        #expect(late.today == friday)
        #expect(blockDays(late) == [friday])
        // Saturday morning: it's still Friday's.
        let morning = state(dayStart: 4, now: saturday.at(hour: 9, minute: 0))
        #expect(morning.today == saturday)
        #expect(blockDays(morning) == [friday])
        #expect(morning.sessions.allSatisfy { $0.day(startingAt: morning.dayStart) != morning.today })
    }

    @Test("with days starting at midnight, the same session is Saturday's")
    func midnightStartKeepsTheCalendarDay() {
        let morning = state(dayStart: 0, now: saturday.at(hour: 9, minute: 0))
        #expect(morning.today == saturday)
        #expect(blockDays(morning) == [saturday])
    }

    @Test("a card due in the small hours is due that evening; a test taken then counts that evening")
    func cardsAndTestsFollowTheDayStart() {
        let card = MemoryCard(
            key: CardKey("jp.word.100001"),
            memory: Memory(stability: 1, difficulty: 5, lastReview: friday.at(hour: 1, minute: 0), due: saturday.at(hour: 1, minute: 0)),
            introduced: friday.at(hour: 1, minute: 0))
        #expect(card.isDue(on: friday, dayStart: 4))
        #expect(!card.isDue(on: friday, dayStart: 0))
        #expect(card.isDue(on: saturday, dayStart: 0))

        let test = TestResult(test: .readingTest, date: saturday.at(hour: 0, minute: 30), score: 0.8, detail: ["tier": 5])
        #expect(test.day(startingAt: 4) == friday)
        #expect(ReadingPlan.level(books: [], tests: [test], on: friday, dayStart: 4) == 5)
        #expect(ReadingPlan.level(books: [], tests: [test], on: friday, dayStart: 0) == nil)
    }

    @Test("settings saved before the choice start their days at 4; odd hours are held to midnight–6 a.m.")
    func settingsDecode() throws {
        func decoded(_ change: (inout [String: Any]) -> Void) throws -> MindSettings {
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Fixtures.settings())) as? [String: Any])
            change(&json)
            return try JSONDecoder().decode(MindSettings.self, from: JSONSerialization.data(withJSONObject: json))
        }
        #expect(try decoded { $0["dayStart"] = nil }.dayStart == 4)
        #expect(try decoded { $0["dayStart"] = 2 }.dayStart == 2)
        #expect(try decoded { $0["dayStart"] = 9 }.dayStart == 6)
        #expect(try decoded { $0["dayStart"] = -3 }.dayStart == 0)
        #expect(MindSettings().dayStart == 4)
        #expect(MindSettings(dayStart: 12).dayStart == 6)
    }
}
