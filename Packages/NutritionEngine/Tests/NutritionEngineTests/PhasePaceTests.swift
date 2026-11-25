import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

@Suite("Pace against the phase")
struct PhasePaceTests {
    let start = Day(year: 2026, month: 11, day: 9)
    var cut: PlannedPhase { PlannedPhase(kind: .cut, ratePerWeek: -0.005, weeks: 4, start: start) }

    @Test("A cut losing about its rate is on pace; much faster or slower says so")
    func cutVerdicts() {
        // 0.5% of 82 kg is 0.41 kg a week.
        #expect(PhasePace.verdict(weeklyChange: -0.41, phase: cut, weightKg: 82) == .onPace)
        #expect(PhasePace.verdict(weeklyChange: -0.32, phase: cut, weightKg: 82) == .onPace)
        #expect(PhasePace.verdict(weeklyChange: -0.55, phase: cut, weightKg: 82) == .onPace)
        #expect(PhasePace.verdict(weeklyChange: -1.09, phase: cut, weightKg: 82) == .faster)
        #expect(PhasePace.verdict(weeklyChange: -0.15, phase: cut, weightKg: 82) == .slower)
        #expect(PhasePace.verdict(weeklyChange: 0.2, phase: cut, weightKg: 82) == .offCourse)
        #expect(PhasePace.verdict(weeklyChange: 0, phase: cut, weightKg: 82) == .offCourse)
    }

    @Test("A bulk gains the other way round")
    func bulk() {
        let bulk = PlannedPhase(kind: .leanBulk, ratePerWeek: 0.0025, weeks: 12, start: start)
        #expect(PhasePace.verdict(weeklyChange: 0.2, phase: bulk, weightKg: 80) == .onPace)
        #expect(PhasePace.verdict(weeklyChange: -0.2, phase: bulk, weightKg: 80) == .offCourse)
    }

    @Test("Maintenance holds within a quarter percent a week")
    func maintenance() {
        let hold = PlannedPhase(kind: .maintenance, ratePerWeek: 0, weeks: 8, start: start)
        #expect(PhasePace.verdict(weeklyChange: 0.15, phase: hold, weightKg: 80) == .onPace)
        #expect(PhasePace.verdict(weeklyChange: -0.4, phase: hold, weightKg: 80) == .offCourse)
    }

    @Test("Nothing to say without a phase or a trend")
    func nothing() {
        #expect(PhasePace.verdict(weeklyChange: nil, phase: cut, weightKg: 82) == nil)
        #expect(PhasePace.verdict(weeklyChange: -0.4, phase: nil, weightKg: 82) == nil)
    }

    @Test("The aim is the phase's rate carried to its last day")
    func aim() throws {
        // Three days in: 25 days left of a −0.5%-a-week cut from 81.4 kg.
        let aim = try #require(PhasePace.aim(trendKg: 81.4, phase: cut, today: start.adding(days: 2)))
        #expect(aim.day == start.adding(days: 27))
        #expect(abs(aim.kg - 81.4 * (1 - 0.005 * 25.0 / 7)) < 0.0001)
        #expect(PhasePace.aim(trendKg: 81.4, phase: cut, today: start.adding(days: 40)) == nil)
        let hold = PlannedPhase(kind: .maintenance, ratePerWeek: 0, weeks: 8, start: start)
        #expect(PhasePace.aim(trendKg: 81.4, phase: hold, today: start) == nil)
    }

    @Test("The next check-in is the Monday nearest a week after the last, or today when it's due")
    func nextCheckIn() {
        // `start` is a Monday.
        let last = CheckIn(
            day: start, expenditure: 2_700, kcal: 2_200, protein: 165, carbs: 240, fat: 65, status: .updated, reason: "Start")
        #expect(PhasePace.nextCheckIn(last: last, today: start.adding(days: 3)) == start.adding(days: 7))
        #expect(PhasePace.nextCheckIn(last: last, today: start.adding(days: 9)) == start.adding(days: 9))
        #expect(PhasePace.nextCheckIn(last: nil, today: start) == start)
        // A plan started on a Thursday checks in on the Monday, and one made late, on a Wednesday,
        // is followed by the next Monday's, five days on.
        var thursday = last
        thursday.day = start.adding(days: 3)
        #expect(PhasePace.nextCheckIn(last: thursday, today: start.adding(days: 4)) == start.adding(days: 7))
        var wednesday = last
        wednesday.day = start.adding(days: 9)
        #expect(PhasePace.nextCheckIn(last: wednesday, today: start.adding(days: 10)) == start.adding(days: 14))
    }
}
