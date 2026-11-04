import Foundation
import Testing

@testable import SystemPurchases

@Suite("Where someone stands")
struct AccessTests {
    private static let start = Date(timeIntervalSince1970: 1_793_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func day(_ days: Int, hours: Int = 0, from start: Date = start) -> Date {
        calendar.date(byAdding: .hour, value: hours, to: calendar.date(byAdding: .day, value: days, to: start)!)!
    }

    private func standing(owned: Ownership? = Ownership(), freeSince: Date? = start, extendedUntil: Date? = nil, at now: Date) -> Standing {
        let record = freeSince == nil && extendedUntil == nil ? nil : AccessRecord(freeSince: freeSince, extendedUntil: extendedUntil, updatedAt: now)
        return Access.standing(owned: owned, record: record, now: now, calendar: calendar)
    }

    @Test("Nobody's anything until the App Store answers, and that counts as paid for")
    func checking() {
        #expect(standing(owned: nil, at: day(100)) == .checking)
        #expect(Standing.checking.unlocked)
    }

    @Test("With no purchase and no free days, the choice is still to make")
    func undecided() {
        #expect(standing(freeSince: nil, at: Self.start) == .undecided)
        #expect(!Standing.undecided.unlocked)
    }

    @Test("A purchase beats everything, the free days included")
    func purchases() {
        #expect(standing(owned: Ownership(lifetime: true), at: day(1)) == .bought)
        #expect(standing(owned: Ownership(subscribed: true), at: day(100)) == .subscribed)
        #expect(standing(owned: Ownership(lifetime: true, subscribed: true), at: day(100)) == .bought)
        #expect(Standing.bought.unlocked && Standing.subscribed.unlocked)
    }

    @Test("Twenty-one days, counted down and never reading zero")
    func freeDays() {
        #expect(standing(at: Self.start) == .free(daysLeft: 21))
        #expect(standing(at: day(0, hours: 1)) == .free(daysLeft: 21))
        #expect(standing(at: day(1)) == .free(daysLeft: 20))
        #expect(standing(at: day(20)) == .free(daysLeft: 1))
        #expect(standing(at: day(20, hours: 23)) == .free(daysLeft: 1))
        #expect(standing(at: day(21)) == .lapsed)
        #expect(Standing.free(daysLeft: 1).unlocked)
        #expect(!Standing.lapsed.unlocked)
    }

    @Test("Days are calendar days, so a clock change neither adds nor takes one")
    func daylightSaving() {
        // 21 days from 12:30 local on 2 Mar 2026, across the change on 8 Mar: 12:30 local on the 23rd.
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 12, minute: 30))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 12, minute: 30))!
        #expect(standing(freeSince: start, at: end.addingTimeInterval(-60)) == .free(daysLeft: 1))
        #expect(standing(freeSince: start, at: end) == .lapsed)
        // One more day over the same night is 23 hours long, and still a day on the clock.
        let night = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 22))!
        let nextNight = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 22))!
        #expect(Access.extended(from: night, calendar: calendar) == nextNight)
    }

    @Test("A clock set back can't show more than the whole allowance")
    func clockSetBack() {
        #expect(standing(at: day(-30)) == .free(daysLeft: Access.freeDays))
    }

    @Test("One more day holds the offer back for a day, then it's due again")
    func oneMoreDay() {
        let tapped = day(25)
        let until = Access.extended(from: tapped, calendar: calendar)
        #expect(standing(extendedUntil: until, at: tapped) == .extended(until: until))
        #expect(standing(extendedUntil: until, at: day(25, hours: 23)) == .extended(until: until))
        #expect(standing(extendedUntil: until, at: until) == .lapsed)
        #expect(Standing.extended(until: until).unlocked)
    }

    @Test("A subscription that ends leaves them where the free days put them")
    func subscriptionEnds() {
        #expect(standing(at: day(5)) == .free(daysLeft: 16))
        #expect(standing(at: day(40)) == .lapsed)
        #expect(standing(freeSince: nil, at: day(40)) == .undecided)
    }
}
