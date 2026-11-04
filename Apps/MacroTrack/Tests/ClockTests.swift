import Foundation
import SystemCore
import Testing

@testable import MacroTrack

/// The logger's time choices: a time picked on the wheel for today lands on the nearest day.
struct LogTimeTests {
    let calendar = Calendar.gregorian(.newYork)

    @Test func lateLastNightPickedJustAfterMidnightIsYesterday() {
        let now = date(2027, 3, 15, 0, 20)
        let picked = date(2027, 3, 15, 23, 30)
        #expect(LogTime.nearest(picked, now: now, calendar: calendar) == date(2027, 3, 14, 23, 30))
    }

    @Test func thisEveningPickedEarlyInTheMorningStaysToday() {
        let picked = date(2027, 3, 15, 18, 30)
        #expect(LogTime.nearest(picked, now: date(2027, 3, 15, 6, 0), calendar: calendar) == picked)
    }

    @Test func lastNightIsWithinSixHoursOfNow() {
        let picked = date(2027, 3, 15, 23, 30)
        #expect(LogTime.nearest(picked, now: date(2027, 3, 15, 5, 0), calendar: calendar) == date(2027, 3, 14, 23, 30))
        #expect(LogTime.nearest(picked, now: date(2027, 3, 15, 6, 0), calendar: calendar) == picked)
    }

    @Test func thisEveningPickedAtNoonStaysToday() {
        let now = date(2027, 3, 15, 12, 0)
        let picked = date(2027, 3, 15, 19, 0)
        #expect(LogTime.nearest(picked, now: now, calendar: calendar) == picked)
    }

    @Test func anEarlierTimeIsLeftAlone() {
        let now = date(2027, 3, 15, 12, 0)
        let picked = date(2027, 3, 15, 8, 0)
        #expect(LogTime.nearest(picked, now: now, calendar: calendar) == picked)
    }

    @Test func yesterdayOverAClockChangeKeepsTheClockTime() {
        // Just after midnight on the day the clocks go forward: 23:30 is the night before, at 23:30,
        // though that's 23 hours before 23:30 tonight, not 24.
        let now = date(2027, 3, 14, 0, 10)
        let picked = date(2027, 3, 14, 23, 30)
        let nearest = LogTime.nearest(picked, now: now, calendar: calendar)
        #expect(calendar.dateComponents([.day, .hour, .minute], from: nearest) == DateComponents(day: 13, hour: 23, minute: 30))
    }

    @Test func recentChoicesReadShort() {
        #expect(LogTime.recent.map(LogTime.ago) == ["30 min ago", "1 h ago", "2 h ago"])
        #expect(LogTime.recent.map(LogTime.short) == ["30m ago", "1h ago", "2h ago"])
    }
}

/// Every editable amount is written by `Format.editable` and read by `Format.parse`: the round trip
/// must give back the number, in any locale, however big.
struct EditableNumberTests {
    @Test(arguments: ["en_US", "en_GB", "de_DE", "fr_FR"])
    func numbersRoundTrip(locale: String) {
        let locale = Locale(identifier: locale)
        for value in [0.5, 1.5, 12.25, 1000, 1200, 1500, 2600.5] {
            let text = Format.editable(value, locale: locale)
            #expect(Format.parse(text) == value, "\(value) was written \(text) in \(locale.identifier)")
        }
    }

    @Test func numbersAreNeverGrouped() {
        #expect(Format.editable(1200, locale: Locale(identifier: "en_US")) == "1200")
        #expect(Format.editable(1234.5, digits: 1, locale: Locale(identifier: "de_DE")) == "1234,5")
        #expect(Format.editable(.nan) == "")
    }

    @Test func typedFractionsParse() {
        #expect(Format.parse("1½") == 1.5)
        #expect(Format.parse("1 1/2") == 1.5)
        #expect(Format.parse("2,5") == 2.5)
        #expect(Format.parse("lots") == nil)
    }
}
