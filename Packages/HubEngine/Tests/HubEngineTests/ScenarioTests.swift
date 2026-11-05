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

/// Twelve weeks of the real shapes a week comes in, lived a day at a time: blocks done or skipped in
/// silence, a night out now and then, a lighter week. Whatever happens, a day's plan has to keep its
/// promises: study never lands in work, sleep or a packed day, and clear evenings stay clear.
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

    func ask(_ monday: Day, finished: [FinishedBlock], now: Date) -> BlockAsk {
        var units: [String: Int] = [:]
        for offset in 0..<14 { units[monday.adding(days: offset).iso] = 2 }
        let courses = [
            BlockCourse(id: "japanese", blocks: 4, fit: [.night, .evening, .afternoon, .midday, .morning, .early]),
            BlockCourse(id: "reading", blocks: 3, fit: [.evening, .night, .afternoon, .midday, .morning, .early]),
            BlockCourse(id: "maths", blocks: 2, fit: [.morning, .midday, .early, .afternoon, .evening, .night]),
            BlockCourse(id: "writing", blocks: 1, fit: [.midday, .afternoon, .morning, .early, .evening, .night]),
        ]
        return BlockAsk(
            monday: monday, since: anchor.adding(weeks: -1), courses: courses, units: units,
            finished: finished.filter { $0.day.startOfWeek == monday },
            updated: now)
    }

    /// What was done, how much of it, and how many blocks a week was planned.
    @discardableResult
    func live(_ rhythm: Rhythm, profile: SharedProfile?, seed: UInt64, weeks: Int = 12) -> (done: Int, planned: Int) {
        var random = Seeded(state: seed)
        var finished: [FinishedBlock] = []
        var changes: [DayChange] = []
        var planned = 0
        let lift = AppSummary(app: .liftTrack, updated: anchor.date(), sessions: [])
        for offset in 0..<(weeks * 7) {
            let today = anchor.adding(days: offset)
            let now = today.at(hour: 7, minute: 0)
            // A night out one day in ten, and the fifth week lighter.
            if random.next() < 0.1 { changes.append(.outTonight(on: today, at: now)) }
            if today.weekday == .monday, offset / 7 == 4 { changes.append(.lighterWeek(of: today, at: now)) }
            var fresh = lift
            fresh.updated = now
            let inputs = HubInputs(
                rhythm: rhythm, changes: changes, profile: profile, lift: profile == nil ? nil : fresh,
                ask: ask(today.startOfWeek, finished: finished, now: now), today: today, now: now)
            let week = HubPlanner.week(of: today, inputs)
            let commitments = HubPlanner.commitments(inputs)
            check(week, from: today, rhythm: rhythm, changes: changes, commitments: commitments)
            if today.weekday == .monday { planned += week.study }
            // A day skipped in silence, or some of its blocks done.
            let skipped = random.next() < 0.2
            for item in week.days.first(where: { $0.day == today })?.items ?? [] where item.kind == .study && !item.done && !skipped {
                if random.next() < 0.8 { finished.append(FinishedBlock(course: item.title.lowercased(), day: today, part: item.part)) }
            }
        }
        return (finished.count, planned)
    }

    /// The promises, for everything from today on.
    func check(_ week: HubWeek, from today: Day, rhythm: Rhythm, changes: [DayChange], commitments: WeekCommitments) {
        let clear = DayShape.clearEvenings(weekOf: week.monday, rhythm: rhythm)
        for day in week.days where day.day >= today {
            let study = day.items.filter { $0.kind == .study && !$0.done }
            #expect(day.parts.allSatisfy { $0.freeMinutes >= 0 }, "\(day.day)")
            for item in study {
                #expect(!changes.closedParts(on: day.day).contains(item.part), "\(item.title) on \(day.day) in a part you're out of")
                if let busy = DayShape.busy(on: day.day, rhythm: rhythm) {
                    #expect(
                        DayShape.longestRun(item.part, busy: busy) >= DayShape.minimumRun, "\(item.title) on \(day.day) in \(item.part) has no room")
                }
            }
            guard day.isKnown else { continue }
            if DayShape.isPacked(day.day.weekday, commitments: commitments) { #expect(study.isEmpty, "\(day.day) is packed") }
            if clear.contains(day.day) {
                #expect(!study.contains { $0.part == .evening || $0.part == .night }, "\(day.day)'s evening is kept clear")
            }
        }
    }

    @Test func nineHoursMonToThuAndAlternateFridays() {
        let long = [DaySpan(.work, "Work", from: at(8), to: at(17, 30))]
        let short = [DaySpan(.work, "Work", from: at(9), to: at(15))]
        let pattern = WorkPattern(anchor: anchor, weeks: [[long, long, long, long, short, [], []], [long, long, long, long, [], [], []]]).withCommute(
            30)
        let rhythm = Rhythm(pattern: pattern, wake: at(5, 45), bed: at(22, 30))
        let result = live(rhythm, profile: classes, seed: 1)
        #expect(result.done > 40, "the week still gets studied")
        let week = HubPlanner.week(
            of: anchor, HubInputs(rhythm: rhythm, profile: classes, today: anchor, now: anchor.date()))
        #expect(week.days[4].items.contains { $0.kind == .work })
        let next = anchor.adding(weeks: 1)
        let off = HubPlanner.week(of: next, HubInputs(rhythm: rhythm, profile: classes, today: next, now: next.date()))
        #expect(!off.days[4].items.contains { $0.kind == .work }, "the other Friday is off")
    }

    @Test func nineToFive() {
        let rhythm = Rhythm(pattern: SchedulePreset.nineToFive.pattern(anchor: anchor).withCommute(45))
        #expect(live(rhythm, profile: nil, seed: 2).done > 40)
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
        #expect(live(rhythm, profile: nil, seed: 4).done > 30)
    }

    @Test func overnightShifts() {
        let night = [DaySpan(.work, "Night shift", from: at(22), to: at(30)), DaySpan(.sleep, "Sleep", from: at(7), to: at(15))]
        let off = [DaySpan(.sleep, "Sleep", from: at(0), to: at(8))]
        let pattern = WorkPattern(anchor: anchor, weeks: [[night, night, night, off, off, off, off]])
        #expect(live(Rhythm(pattern: pattern), profile: nil, seed: 5).done > 20)
    }

    @Test func nothingFixedStillGetsAWeek() {
        #expect(live(Rhythm(pattern: SchedulePreset.nothingFixed.pattern(anchor: anchor)), profile: classes, seed: 6).done > 40)
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
