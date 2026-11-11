import Foundation
import SystemCore
import Testing

@testable import HubEngine

/// A small seeded generator: the same twelve weeks every run.
private struct Seeded {
    var state: UInt64

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((state >> 33) % 10_000) / 10_000
    }
}

/// Twelve weeks of the real shapes a week comes in, lived a day at a time: sessions done or skipped in
/// silence, a night out now and then, a lighter week. Whatever happens, a day's plan has to keep its
/// promises: nothing of yours lands in a part you're out of, a part never holds more than it has
/// room for, and the gym is never asked for more often than Stadig Lift plans it.
@Suite("Twelve weeks of real weeks")
struct ScenarioTests {
    let anchor = Day(year: 2026, month: 9, day: 7)

    func at(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    var classes: SharedProfile {
        SharedProfile(
            schedule: TrainingSchedule(daysPerWeek: 5, minutesPerSession: 90, preferredDays: [.monday, .tuesday, .wednesday, .thursday, .friday]),
            recurring: [
                RecurringActivity(activity: .bjj, weekdays: [.monday, .wednesday], minutes: 60),
                RecurringActivity(activity: .muayThai, weekdays: [.monday, .wednesday, .friday], minutes: 60),
            ],
            createdBy: .liftTrack)
    }

    /// How many gym sessions were done, and how many the weeks planned.
    @discardableResult
    func live(_ rhythm: Rhythm, profile: SharedProfile?, seed: UInt64, weeks: Int = 12) -> (done: Int, planned: Int) {
        var random = Seeded(state: seed)
        var sessions: [SessionSummary] = []
        var changes: [DayChange] = []
        var planned = 0
        for offset in 0..<(weeks * 7) {
            let today = anchor.adding(days: offset)
            let now = today.at(hour: 7, minute: 0)
            // A night out one day in ten, and the fifth week lighter.
            if random.next() < 0.1 { changes.append(.outTonight(on: today, at: now)) }
            if today.weekday == .monday, offset / 7 == 4 { changes.append(.lighterWeek(of: today, at: now)) }
            let lift = AppSummary(app: .liftTrack, updated: now, sessions: sessions)
            let meals = MealRhythm(usual: [.early, .midday, .evening], day: today, eaten: [], updated: now)
            let inputs = HubInputs(
                rhythm: rhythm, changes: changes, profile: profile, lift: profile == nil ? nil : lift, meals: meals, today: today, now: now)
            let week = HubPlanner.week(of: today, inputs)
            check(week, from: today, changes: changes, sessionsAWeek: profile?.schedule.daysPerWeek ?? 0)
            if today.weekday == .monday { planned += week.gym }
            // A day skipped in silence, or its session done.
            let skipped = random.next() < 0.2
            for item in week.days.first(where: { $0.day == today })?.items ?? [] where item.kind == .lift && !item.done && !skipped {
                if random.next() < 0.8 {
                    sessions.append(SessionSummary(id: UUID(), app: .liftTrack, kind: .strength, start: now, minutes: item.minutes, planned: true))
                }
            }
        }
        return (sessions.count, planned)
    }

    /// The promises, for everything from today on.
    func check(_ week: HubWeek, from today: Day, changes: [DayChange], sessionsAWeek: Int) {
        #expect(week.gym <= sessionsAWeek, "the week of \(week.monday)")
        for day in week.days where day.day >= today {
            let closed = changes.closedParts(on: day.day)
            for part in day.parts {
                #expect(part.freeMinutes >= 0 && part.freeMinutes <= part.part.minutes.count, "\(day.day) \(part.part)")
                #expect(part.isClosed == closed.contains(part.part))
                if part.isClosed { #expect(!part.items.contains { $0.isYours && !$0.done }, "\(day.day): something in a part you're out of") }
            }
            #expect(day.items.filter { $0.kind == .lift }.count <= 1, "\(day.day)")
        }
    }

    @Test func nineHoursMonToThuAndAlternateFridays() {
        let long = [DaySpan(.work, "Work", from: at(8), to: at(17, 30))]
        let short = [DaySpan(.work, "Work", from: at(9), to: at(15))]
        let pattern = WorkPattern(anchor: anchor, weeks: [[long, long, long, long, short, [], []], [long, long, long, long, [], [], []]]).withCommute(
            30)
        let rhythm = Rhythm(pattern: pattern, wake: at(5, 45), bed: at(22, 30))
        let result = live(rhythm, profile: classes, seed: 1)
        #expect(result.done > 30, "the week still gets trained")
        #expect(result.done <= result.planned)
        let week = HubPlanner.week(
            of: anchor, HubInputs(rhythm: rhythm, profile: classes, today: anchor, now: anchor.date()))
        #expect(week.days[4].items.contains { $0.kind == .work })
        let next = anchor.adding(weeks: 1)
        let off = HubPlanner.week(of: next, HubInputs(rhythm: rhythm, profile: classes, today: next, now: next.date()))
        #expect(!off.days[4].items.contains { $0.kind == .work }, "the other Friday is off")
    }

    @Test func nineToFive() {
        let rhythm = Rhythm(pattern: SchedulePreset.nineToFive.pattern(anchor: anchor).withCommute(45))
        #expect(live(rhythm, profile: nil, seed: 2) == (0, 0), "with no training days there's no gym to plan")
    }

    @Test func universityPastTheEndOfTerm() {
        var pattern = SchedulePreset.university.pattern(anchor: anchor)
        pattern.endsOn = anchor.adding(weeks: 8)
        let rhythm = Rhythm(pattern: pattern)
        #expect(live(rhythm, profile: classes, seed: 3).done > 30)
        let after = anchor.adding(weeks: 9)
        #expect(
            !HubPlanner.day(on: after, HubInputs(rhythm: rhythm, today: after, now: after.date())).isKnown, "it says so rather than calling it free")
    }

    @Test func rotatingShifts() {
        let rhythm = Rhythm(pattern: SchedulePreset.rotatingShifts.pattern(anchor: anchor))
        live(rhythm, profile: nil, seed: 4)
    }

    @Test func overnightShifts() {
        let night = [DaySpan(.work, "Night shift", from: at(22), to: at(30)), DaySpan(.sleep, "Sleep", from: at(7), to: at(15))]
        let off = [DaySpan(.sleep, "Sleep", from: at(0), to: at(8))]
        let pattern = WorkPattern(anchor: anchor, weeks: [[night, night, night, off, off, off, off]])
        #expect(live(Rhythm(pattern: pattern), profile: classes, seed: 5).done > 0)
    }

    @Test func nothingFixedStillGetsAWeek() {
        #expect(live(Rhythm(pattern: SchedulePreset.nothingFixed.pattern(anchor: anchor)), profile: classes, seed: 6).done > 30)
    }

    @Test func noWorkPatternAtAll() {
        #expect(live(Rhythm(), profile: classes, seed: 7).done > 0)
    }

    /// Different seeds, so one lucky run can't hide a broken promise.
    @Test(arguments: 10..<20)
    func theSamePromisesWhateverHappens(seed: Int) {
        let pattern = SchedulePreset.alternateFridays.pattern(anchor: anchor).withCommute(30)
        live(Rhythm(pattern: pattern), profile: classes, seed: UInt64(seed))
    }
}
