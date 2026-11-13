import Foundation
import Testing

@testable import SystemCore

/// How a score has moved: the dated readings each app records as it publishes its stats, and the
/// change over a month, since a named month or since a check-in that both apps show beside a score.
@Suite("Score history")
struct ScoreHistoryTests {
    let utc = TimeZone(identifier: "UTC")!
    let today = Day(year: 2026, month: 11, day: 13)

    var english: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    func reading(_ stat: StatKind, _ score: Double?) -> StatReading {
        StatReading(stat: stat, score: score, label: "", trend: .notEnoughData, updated: Date(timeIntervalSince1970: 0))
    }

    /// One reading on each of these days back from `today`, oldest first.
    func points(_ scores: [(back: Int, score: Double)]) -> [ScorePoint] {
        scores.map { ScorePoint(day: today.adding(days: -$0.back), score: $0.score) }.sorted { $0.day < $1.day }
    }

    // MARK: Recording

    @Test func aDayKeepsItsLastReadingToATenth() {
        var history = ScoreHistory(app: .liftTrack)
        history = history.recording([reading(.strength, 56.04), reading(.physique, nil)], on: today)
        history = history.recording([reading(.strength, 57.26), reading(.endurance, 48)], on: today)
        #expect(history.points(.strength) == [ScorePoint(day: today, score: 57.3)])
        #expect(history.points(.endurance) == [ScorePoint(day: today, score: 48)])
        #expect(history.points(.physique).isEmpty, "a stat with no score yet records nothing")
        history = history.recording([reading(.strength, 58), reading(.agility, .nan), reading(.vitality, 140)], on: today.adding(days: 1))
        #expect(history.points(.strength).map(\.score) == [57.3, 58])
        #expect(history.points(.agility).isEmpty)
        #expect(history.points(.vitality).map(\.score) == [100])
    }

    /// The day is the one the phone's clock shows: a publish at half past eleven and one at half past
    /// midnight are two days, through the night the clocks change too.
    @Test func daysFollowTheClockThroughDaylightSaving() throws {
        var oslo = Calendar(identifier: .gregorian)
        oslo.timeZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        let springEve = Day(year: 2026, month: 3, day: 28)
        let spring = springEve.adding(days: 1)
        var history = ScoreHistory(app: .liftTrack)
        for (day, hour, minute, score) in [
            (springEve, 23, 30, 50.0), (spring, 0, 30, 51), (spring, 1, 59, 52), (spring, 3, 0, 53), (spring, 23, 59, 54),
        ] {
            history = history.recording([reading(.strength, score)], at: day.at(hour: hour, minute: minute, timeZone: oslo.timeZone), calendar: oslo)
        }
        #expect(history.points(.strength) == [ScorePoint(day: springEve, score: 50), ScorePoint(day: spring, score: 54)])

        // New York falls back on 1 November 2026: half past one comes twice, an hour apart, on the same day.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let fallBack = Day(year: 2026, month: 11, day: 1)
        let first = fallBack.at(hour: 1, minute: 30, timeZone: newYork.timeZone)
        history = ScoreHistory(app: .macroTrack)
            .recording([reading(.vitality, 70)], at: first, calendar: newYork)
            .recording([reading(.vitality, 71)], at: first.addingTimeInterval(3600), calendar: newYork)
            .recording(
                [reading(.vitality, 72)], at: fallBack.at(hour: 23, minute: 59, timeZone: newYork.timeZone).addingTimeInterval(120), calendar: newYork
            )
        #expect(history.points(.vitality) == [ScorePoint(day: fallBack, score: 71), ScorePoint(day: fallBack.adding(days: 1), score: 72)])
    }

    /// Flown west over the date line, the phone's next reading is on the day before its last. Both
    /// stay, in day order, and the change is still measured from before the window.
    @Test func aPhoneFlownOverTheDateLineKeepsItsDaysInOrder() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        var honolulu = Calendar(identifier: .gregorian)
        honolulu.timeZone = try #require(TimeZone(identifier: "Pacific/Honolulu"))
        let departure = today.at(hour: 1, minute: 0, timeZone: tokyo.timeZone)
        var history = ScoreHistory(app: .liftTrack).recording([reading(.strength, 50)], on: today.adding(days: -40))
        history = history.recording([reading(.strength, 55)], at: departure, calendar: tokyo)
        history = history.recording([reading(.strength, 56)], at: departure.addingTimeInterval(8 * 3600), calendar: honolulu)
        #expect(history.points(.strength).map(\.day) == [today.adding(days: -40), today.adding(days: -1), today])
        #expect(history.points(.strength).map(\.score) == [50, 56, 55])
        let change = try #require(ScoreChange.measure(history.points(.strength), now: 56, over: .month, today: today.adding(days: -1)))
        #expect(change.whole == 6)
    }

    // MARK: Keeping it small

    /// Two and a half years of a reading every day: the last nine weeks whole, each week's and
    /// month's last before that, nothing past two years, and the same again if thinned twice.
    @Test func oldReadingsThinToWeeksAndMonths() {
        let start = today.adding(days: -913)
        var history = ScoreHistory(app: .liftTrack)
        var day = start
        while day <= today {
            history = history.recording([reading(.strength, Double(day.ordinal % 100))], on: day)
            day = day.adding(days: 1)
        }
        let points = history.points(.strength)
        #expect(points.count < 200, "\(points.count) readings")
        #expect(points.last?.day == today)
        #expect(points.first.map { $0.day.days(until: today) <= ScoreHistory.horizonDays } == true)
        let recent = points.filter { $0.day.days(until: today) <= ScoreHistory.dailyDays }
        #expect(recent.count == ScoreHistory.dailyDays + 1)
        for (point, next) in zip(points, points.dropFirst()).dropFirst() where point.day.days(until: today) > ScoreHistory.dailyDays {
            #expect(next.day.startOfWeek != point.day.startOfWeek || next.day.firstOfMonth != point.day.firstOfMonth, "\(point.day)")
        }
        // Every month's last day is still there, so "since" a month is measured from the day itself.
        var month = today.adding(months: -23).firstOfMonth
        while month <= today.firstOfMonth {
            #expect(points.contains { $0.day == month.adding(days: -1) }, "\(month.adding(days: -1))")
            month = month.adding(months: 1)
        }
        #expect(history.thinned(today: today) == history)
    }

    /// Another device's copy: every day either has, the other's on a day both have.
    @Test func copiesFromTwoDevicesMerge() {
        let phone = ScoreHistory(app: .liftTrack, stats: [.strength: points([(10, 50), (9, 51), (2, 54)]), .agility: points([(3, 60)])])
        let pad = ScoreHistory(app: .liftTrack, stats: [.strength: points([(9, 51.5), (5, 53)]), .endurance: points([(1, 40)])])
        let merged = phone.merged(with: pad)
        #expect(merged.points(.strength) == points([(10, 50), (9, 51.5), (5, 53), (2, 54)]))
        #expect(merged.points(.agility) == points([(3, 60)]))
        #expect(merged.points(.endurance) == points([(1, 40)]))
        #expect(merged.app == .liftTrack)
        #expect(phone.merged(with: ScoreHistory(app: .liftTrack)) == phone)
    }

    @Test func monthsAddByTheCalendar() {
        #expect(Day(year: 2027, month: 3, day: 31).adding(months: -1) == Day(year: 2027, month: 2, day: 28))
        #expect(Day(year: 2028, month: 3, day: 31).adding(months: -1) == Day(year: 2028, month: 2, day: 29))
        #expect(Day(year: 2026, month: 1, day: 31).adding(months: 1) == Day(year: 2026, month: 2, day: 28))
        #expect(Day(year: 2026, month: 1, day: 15).adding(months: -1) == Day(year: 2025, month: 12, day: 15))
        #expect(Day(year: 2026, month: 11, day: 13).adding(months: -26) == Day(year: 2024, month: 9, day: 13))
        #expect(Day(year: 2026, month: 12, day: 31).adding(months: 2) == Day(year: 2027, month: 2, day: 28))
        #expect(Day(year: 2026, month: 11, day: 13).firstOfMonth == Day(year: 2026, month: 11, day: 1))
    }

    // MARK: Measuring

    /// Someone new: nothing to measure from on the first day, nor until the first reading is a week
    /// old. Then the change since they began, which happened this month.
    @Test func aFirstReadingSaysNothingForAWeek() throws {
        #expect(ScoreChange.measure([], now: 50, over: .month, today: today) == nil)
        #expect(ScoreChange.measure(points([(0, 50)]), now: 50, over: .month, today: today) == nil)
        #expect(ScoreChange.measure(points([(6, 48), (0, 50)]), now: 50, over: .month, today: today) == nil)
        let change = try #require(ScoreChange.measure(points([(7, 48), (0, 50)]), now: 50, over: .month, today: today))
        #expect(change.from == today.adding(days: -7))
        #expect(change.text(calendar: english) == "+2 this month")
        #expect(ScoreChange.measure(points([(10, 48)]), now: nil, over: .month, today: today) == nil)
    }

    /// From the score as it stood a month ago today: the reading on that day, not one after it.
    @Test func thisMonthIsSinceThisDateLastMonth() throws {
        let history = points([(40, 40), (31, 45), (30, 52), (29, 53), (1, 55)])
        let change = try #require(ScoreChange.measure(history, now: 57.4, over: .month, today: today))
        #expect(today.adding(days: -31) == Day(year: 2026, month: 10, day: 13))
        #expect(change.from == Day(year: 2026, month: 10, day: 13))
        #expect(change.then == 45)
        #expect(change.whole == 12)
        // From the last day of March, a month back is the end of February.
        let march = Day(year: 2027, month: 3, day: 31)
        #expect(ScoreWindow.month.start(today: march) == Day(year: 2027, month: 3, day: 1))
    }

    /// Under a point either way is steady; a point is +1; half a point more rounds away from zero.
    @Test func steadyIsUnderAPoint() throws {
        let history = points([(35, 60)])
        func change(_ now: Double) throws -> ScoreChange {
            try #require(ScoreChange.measure(history, now: now, over: .month, today: today))
        }
        #expect(try change(60.9).short == "steady")
        #expect(try change(59.1).short == "steady")
        #expect(try change(60.9).direction == .steady)
        #expect(try change(60.9).text(calendar: english) == "Steady this month")
        #expect(try change(60.9).spoken(calendar: english) == "steady this month")
        #expect(try change(61).short == "+1")
        #expect(try change(61.49).short == "+1")
        #expect(try change(61.5).short == "+2")
        #expect(try change(64).spoken(calendar: english) == "up 4 this month")
    }

    /// A score that falls says so, with a minus sign rather than a hyphen.
    @Test func aFallingScore() throws {
        let change = try #require(ScoreChange.measure(points([(33, 75), (12, 74)]), now: 72.2, over: .month, today: today))
        #expect(change.direction == .down)
        #expect(change.whole == -3)
        #expect(change.short == "\u{2212}3")
        #expect(change.text(calendar: english) == "\u{2212}3 this month")
        #expect(change.spoken(calendar: english) == "down 3 this month")
        let small = try #require(ScoreChange.measure(points([(33, 75)]), now: 73.8, over: .month, today: today))
        #expect(small.short == "\u{2212}1")
    }

    /// A reading from long before the window doesn't speak for its start: the app went unused, and
    /// the score may have moved unrecorded. Then the change is since the readings began again, once
    /// that's a week ago, or nothing.
    @Test func aGapLeavesTheOldReadingOut() throws {
        // Last opened 80 days ago, back 10 days ago.
        let back = points([(80, 40), (10, 45), (3, 47)])
        let change = try #require(ScoreChange.measure(back, now: 48, over: .month, today: today))
        #expect(change.from == today.adding(days: -10))
        #expect(change.whole == 3)
        // Back 4 days ago: nothing yet.
        #expect(ScoreChange.measure(points([(80, 40), (4, 45)]), now: 48, over: .month, today: today) == nil)
        // A reading up to five weeks before the window's start still counts; a day more and it doesn't.
        let start = ScoreWindow.month.start(today: today)
        let edge = [ScorePoint(day: start.adding(days: -35), score: 40), ScorePoint(day: today.adding(days: -2), score: 47)]
        #expect(try #require(ScoreChange.measure(edge, now: 48, over: .month, today: today)).then == 40)
        #expect(ScoreHistory.standing([ScorePoint(day: start.adding(days: -36), score: 40)], before: start) == nil)
    }

    /// "Since August" is from the score as August began; with readings only since October, it says
    /// "since October"; this month's is "this month"; a year back names the year.
    @Test func sinceAMonth() throws {
        let august = Day(year: 2026, month: 8, day: 19)
        let history = [
            ScorePoint(day: Day(year: 2026, month: 7, day: 30), score: 58), ScorePoint(day: Day(year: 2026, month: 7, day: 31), score: 61),
            ScorePoint(day: Day(year: 2026, month: 8, day: 1), score: 70), ScorePoint(day: today, score: 64),
        ]
        let change = try #require(ScoreChange.measure(history, now: 64, over: .since(month: august), today: today))
        #expect(change.then == 61)
        #expect(change.text(calendar: english) == "+3 since August")
        #expect(StatsBoard.lookBack(today: today) == .since(month: Day(year: 2026, month: 8, day: 13)))

        let october = points([(20, 50), (0, 52)])
        let later = try #require(ScoreChange.measure(october, now: 52, over: .since(month: august), today: today))
        #expect(later.text(calendar: english) == "+2 since October")

        let thisMonth = points([(12, 50)])
        let now = try #require(ScoreChange.measure(thisMonth, now: 52, over: .since(month: august), today: today))
        #expect(now.period == .thisMonth)
        #expect(now.text(calendar: english) == "+2 this month")

        let lastNovember = [ScorePoint(day: Day(year: 2025, month: 10, day: 31), score: 40)]
        let year = try #require(ScoreChange.measure(lastNovember, now: 52, over: .since(month: Day(year: 2025, month: 11, day: 1)), today: today))
        #expect(year.text(calendar: english) == "+12 since November 2025")
        let december = [ScorePoint(day: Day(year: 2025, month: 11, day: 30), score: 40)]
        let notYet = try #require(ScoreChange.measure(december, now: 52, over: .since(month: Day(year: 2025, month: 12, day: 1)), today: today))
        #expect(notYet.text(calendar: english) == "+12 since December")
    }

    /// Since a check-in: measured from before its day, so what the check-in changed counts.
    @Test func sinceTheLastCheckIn() throws {
        let checkIn = today.adding(days: -2)
        let history = points([(9, 60), (3, 61), (2, 63)])
        let change = try #require(ScoreChange.measure(history, now: 63.2, over: .sinceCheckIn(checkIn), today: today))
        #expect(change.then == 61)
        #expect(change.text(calendar: english) == "+2 since the last check-in")
    }

    /// Discipline, which both apps publish, moves by the average of their changes; an app with
    /// nothing to measure from yet doesn't count as the score moving.
    @Test func twoAppsChangesAverage() throws {
        let lift = points([(31, 80), (0, 88)])
        let macro = points([(31, 90), (0, 86)])
        let both = try #require(ScoreChange.measure([(lift, 88), (macro, 86)], over: .month, today: today))
        #expect(both.points == 2)
        #expect(both.then == 85)
        let newMacro = try #require(ScoreChange.measure([(lift, 88), (points([(2, 70)]), 86)], over: .month, today: today))
        #expect(newMacro.points == 8)
        #expect(ScoreChange.measure([(points([(2, 70)]), 86)], over: .month, today: today) == nil)
    }

    /// Month names come from the calendar's locale, for the Gregorian month whatever the calendar.
    @Test func monthNames() {
        let august = ScoreChange.Period.since(month: Day(year: 2026, month: 8, day: 1), withYear: false)
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.locale = Locale(identifier: "en_US_POSIX")
        #expect(august.words(calendar: hebrew) == "since August", "a day is always a Gregorian date")
        #expect(ScoreChange.Period.since(month: Day(year: 2025, month: 11, day: 1), withYear: true).monthName(calendar: english) == "November 2025")
        #expect(ScoreChange.Period.thisMonth.monthName(calendar: english) == nil)
    }

    // MARK: A person over months

    /// Seven months of someone in Oslo opening the app at all hours, sometimes three times a day and
    /// sometimes not for days, nine weeks away in the middle, their strength climbing and their
    /// discipline sliding for a month. Every day, "this month" and "since" the look-back month are
    /// what the true scores say, measured from the last day they published before the window.
    @Test func aPersonOverSevenMonths() throws {
        var oslo = Calendar(identifier: .gregorian)
        oslo.timeZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        oslo.locale = Locale(identifier: "en_US_POSIX")
        let first = Day(year: 2026, month: 2, day: 2)
        let away = DayRange(Day(year: 2026, month: 5, day: 4), Day(year: 2026, month: 7, day: 5))
        let slump = DayRange(Day(year: 2026, month: 7, day: 20), Day(year: 2026, month: 8, day: 19))
        func strength(_ day: Day) -> Double { 40 + 0.07 * Double(first.days(until: day)) + 1.5 * sin(Double(day.ordinal) / 5) }
        func discipline(_ day: Day) -> Double {
            if day < slump.start { return 82 }
            if slump.contains(day) { return 82 - 0.4 * Double(slump.start.days(until: day)) }
            return 70 + 0.1 * Double(slump.end.days(until: day))
        }
        var random = SplitMix(seed: 2026)
        var history = ScoreHistory(app: .liftTrack)
        var published: [Day] = []
        var day = first
        let last = Day(year: 2026, month: 8, day: 31)
        var checked = 0
        while day <= last {
            let opens = away.contains(day) ? 0 : Int(random.next() % 4)
            if opens > 0 {
                // Times of day, the last of them near midnight now and then.
                let minutes = (0..<opens).map { _ in Int(random.next() % (24 * 60)) }.sorted()
                for (index, minute) in minutes.enumerated() {
                    let lastOfDay = index == minutes.count - 1
                    let earlier = lastOfDay ? 0 : 0.3
                    let at = day.at(hour: minute / 60, minute: minute % 60, timeZone: oslo.timeZone)
                    history = history.recording(
                        [reading(.strength, strength(day) - earlier), reading(.discipline, discipline(day) - earlier)], at: at,
                        calendar: oslo)
                }
                published.append(day)
            }
            #expect(Set(history.points(.strength).map(\.day)).count == history.points(.strength).count)
            if published.last == day {
                for (stat, truth) in [(StatKind.strength, strength), (.discipline, discipline)] {
                    for window in [ScoreWindow.month, StatsBoard.lookBack(today: day)] {
                        let start = window.start(today: day)
                        let change = ScoreChange.measure(history.points(stat), now: truth(day), over: window, today: day)
                        let before = published.last { $0 < start }.flatMap { $0.days(until: start) <= ScoreHistory.gapDays ? $0 : nil }
                        let since = published.first { $0 >= start && $0 < day && $0.days(until: day) >= ScoreChange.minimumDays }
                        if let from = before ?? since {
                            let measured = try #require(change, "\(stat) over \(window) on \(day)")
                            #expect(measured.from == from, "\(stat) over \(window) on \(day)")
                            #expect(abs(measured.points - (truth(day) - truth(from))) < 0.06, "\(stat) over \(window) on \(day)")
                            checked += 1
                        } else {
                            #expect(change == nil, "\(stat) over \(window) on \(day)")
                        }
                    }
                }
            }
            day = day.adding(days: 1)
        }
        #expect(checked > 300)
        // Back from nine weeks away: on the day, the month is measured across the gap from the last
        // day before it; a week on, the last day before it is too long before the month began, so
        // from the first day back.
        let lastBefore = try #require(published.last { $0 < away.start })
        let back = try #require(published.first { $0 > away.end })
        let onTheDay = try #require(ScoreChange.measure(history.points(.strength), now: strength(back), over: .month, today: back))
        #expect(onTheDay.from == lastBefore)
        let weekOn = try #require(published.first { $0 >= back.adding(days: 7) })
        let afterBreak = try #require(ScoreChange.measure(history.points(.strength), now: strength(weekOn), over: .month, today: weekOn))
        #expect(afterBreak.from == back)
        // The slump reads as a fall, the climb as a rise.
        let endOfSlump = try #require(published.last { slump.contains($0) && $0 > slump.start.adding(days: 25) })
        let slide = try #require(ScoreChange.measure(history.points(.discipline), now: discipline(endOfSlump), over: .month, today: endOfSlump))
        #expect(slide.direction == .down)
        #expect(slide.text(calendar: oslo).hasPrefix("\u{2212}"))
        let summer = try #require(
            ScoreChange.measure(history.points(.strength), now: strength(last), over: StatsBoard.lookBack(today: last), today: last))
        #expect(summer.text(calendar: oslo).hasSuffix("since May"))
        #expect(summer.direction == .up)
    }
}

/// A seeded generator, so the simulated person is the same every run.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
