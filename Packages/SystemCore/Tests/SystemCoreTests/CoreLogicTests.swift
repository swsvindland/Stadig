import Foundation
import Testing

@testable import SystemCore

@Suite("Days")
struct DayTests {
    @Test func arithmeticAndWeekdays() {
        let day = Day(year: 2026, month: 10, day: 15)
        #expect(day.weekday == .thursday)
        #expect(day.iso == "2026-10-15")
        #expect(Day(iso: "2026-10-15") == day)
        #expect(day.adding(days: 17) == Day(year: 2026, month: 11, day: 1))
        #expect(Day(year: 2024, month: 3, day: 1).adding(days: -1) == Day(year: 2024, month: 2, day: 29))
        #expect(day.startOfWeek == Day(year: 2026, month: 10, day: 12))
        #expect(Day(ordinal: 0).iso == "1970-01-01")
        let data = try! JSONEncoder().encode([day])
        #expect(String(data: data, encoding: .utf8) == "[\"2026-10-15\"]")
    }

    static func gregorian(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    @Test(arguments: [Calendar.Identifier.buddhist, .japanese, .hebrew, .islamicUmmAlQura, .persian])
    func aPhoneOnAnotherCalendarStillCountsGregorianDays(_ identifier: Calendar.Identifier) throws {
        var device = Calendar(identifier: identifier)
        device.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let noon = try #require(Self.gregorian("Asia/Bangkok").date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12)))
        let day = Day(noon, calendar: device)
        // Sunday 18 October 2026, not Buddhist 2569 (a Wednesday) or Reiwa 8.
        #expect(day == Day(year: 2026, month: 10, day: 18))
        #expect(day.weekday == .sunday)
        #expect(day.iso == "2026-10-18")
        #expect(day.date(calendar: device) == Self.gregorian("Asia/Bangkok").startOfDay(for: noon))
        // Every real day is the next Day, across the other calendar's month and year ends.
        for offset in 0..<400 {
            let date = noon.addingTimeInterval(Double(offset) * 86_400)
            #expect(Day(date, calendar: device) == day.adding(days: offset))
            #expect(Day(Day(date, calendar: device).date(calendar: device), calendar: device) == day.adding(days: offset))
        }
    }

    @Test func daysFollowTheTimeZoneAndItsClockChanges() throws {
        // 06:30 UTC on 8 March 2026 is still the 7th in Los Angeles and already the 8th in Tokyo.
        let moment = try #require(Self.gregorian("UTC").date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 6, minute: 30)))
        #expect(Day(moment, timeZone: TimeZone(identifier: "America/Los_Angeles")!) == Day(year: 2026, month: 3, day: 7))
        #expect(Day(moment, timeZone: TimeZone(identifier: "Asia/Tokyo")!) == Day(year: 2026, month: 3, day: 8))
        // Agrees with the Gregorian calendar every six hours for three years, daylight saving included.
        for zone in ["America/New_York", "Europe/London", "Australia/Sydney", "Asia/Kolkata"] {
            let calendar = Self.gregorian(zone)
            for step in 0..<(3 * 365 * 4) {
                let date = moment.addingTimeInterval(Double(step) * 6 * 3600)
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                #expect(Day(date, calendar: calendar) == Day(year: parts.year!, month: parts.month!, day: parts.day!))
            }
        }
        // New York springs forward on 8 March: that day starts at 05:00 UTC, the next at 04:00.
        let newYork = TimeZone(identifier: "America/New_York")!
        #expect(Day(year: 2026, month: 3, day: 8).date(timeZone: newYork) == moment.addingTimeInterval(-1.5 * 3600))
        #expect(Day(year: 2026, month: 3, day: 9).date(timeZone: newYork) == moment.addingTimeInterval(21.5 * 3600))
        // São Paulo's clocks skipped midnight on 4 November 2018: the day starts at its first moment.
        let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!
        let skipped = Day(year: 2018, month: 11, day: 4)
        let start = skipped.date(timeZone: saoPaulo)
        #expect(Day(start, timeZone: saoPaulo) == skipped)
        #expect(Day(start.addingTimeInterval(-1), timeZone: saoPaulo) == skipped.adding(days: -1))
    }

    /// New York's clocks go forward on 14 March 2027 (a 23-hour day) and back on 7 November (25 hours).
    @Test(arguments: [Day(year: 2027, month: 3, day: 14), Day(year: 2027, month: 11, day: 7)])
    func aTimeOnTheClockKeepsItsTimeAndItsDayWhenTheClocksChange(_ day: Day) throws {
        let newYork = TimeZone(identifier: "America/New_York")!
        let clock = Self.gregorian("America/New_York")
        for (hour, minute) in [(7, 0), (23, 30)] {
            let time = day.at(hour: hour, minute: minute, timeZone: newYork)
            let shown = clock.dateComponents([.hour, .minute], from: time)
            #expect(shown.hour == hour && shown.minute == minute, "\(day) \(hour):\(minute)")
            #expect(Day(time, timeZone: newYork) == day)
            #expect(day.at(minutes: hour * 60 + minute, timeZone: newYork) == time)
            // The same time of day taken from another day, with no clock change.
            let other = try #require(clock.date(from: DateComponents(year: 2027, month: 6, day: 1, hour: hour, minute: minute)))
            #expect(day.at(sameTimeAs: other, timeZone: newYork) == time)
            // Midnight plus the hours would be an hour off, or on the next day.
            #expect(time != day.date(timeZone: newYork).addingTimeInterval(Double(hour * 3600 + minute * 60)))
        }
    }

    @Test func aTimeTheClocksSkipComesOutJustAfterTheChange() throws {
        let newYork = TimeZone(identifier: "America/New_York")!
        let day = Day(year: 2027, month: 3, day: 14)
        let time = day.at(hour: 2, minute: 30, timeZone: newYork)
        let shown = Self.gregorian("America/New_York").dateComponents([.hour, .minute], from: time)
        #expect(shown.hour == 3 && shown.minute == 30)
        #expect(Day(time, timeZone: newYork) == day)
    }

    /// A day that starts at 4 keeps the small hours with the evening before, by the clock, on the
    /// nights the clocks go forward (14 March 2027) and back (7 November) too.
    @Test(arguments: [Day(year: 2027, month: 3, day: 14), Day(year: 2027, month: 11, day: 7), Day(year: 2027, month: 6, day: 1)])
    func aDayThatStartsAtFourKeepsTheSmallHoursWithTheNightBefore(_ day: Day) {
        let newYork = TimeZone(identifier: "America/New_York")!
        let evening = day.adding(days: -1)
        for (hour, minute) in [(0, 0), (1, 30), (3, 59)] {
            #expect(Day(day.at(hour: hour, minute: minute, timeZone: newYork), dayStartsAt: 4, timeZone: newYork) == evening, "\(hour):\(minute)")
        }
        let four = day.at(hour: 4, minute: 0, timeZone: newYork)
        #expect(Day(four, dayStartsAt: 4, timeZone: newYork) == day)
        #expect(Day(four.addingTimeInterval(-1), dayStartsAt: 4, timeZone: newYork) == evening)
        #expect(Day(day.at(hour: 23, minute: 59, timeZone: newYork), dayStartsAt: 4, timeZone: newYork) == day)
        // Starting at midnight is the plain calendar day.
        for hour in [0, 3, 12, 23] {
            let time = day.at(hour: hour, minute: 0, timeZone: newYork)
            #expect(Day(time, dayStartsAt: 0, timeZone: newYork) == Day(time, timeZone: newYork))
        }
    }

    @Test(arguments: [Calendar.Identifier.buddhist, .japanese])
    func aPhoneOnAnotherCalendarGetsTheSameTimes(_ identifier: Calendar.Identifier) throws {
        var device = Calendar(identifier: identifier)
        device.timeZone = TimeZone(identifier: "America/New_York")!
        let gregorian = Self.gregorian("America/New_York")
        for day in [Day(year: 2027, month: 3, day: 14), Day(year: 2027, month: 11, day: 7)] {
            let time = day.at(hour: 7, minute: 0, calendar: device)
            #expect(time == day.at(hour: 7, minute: 0, timeZone: gregorian.timeZone))
            #expect(time == gregorian.date(from: DateComponents(year: day.year, month: day.month, day: day.dayOfMonth, hour: 7)))
            #expect(day.at(minutes: 23 * 60 + 30, calendar: device) == day.at(hour: 23, minute: 30, timeZone: gregorian.timeZone))
            #expect(day.at(sameTimeAs: time, calendar: device) == time)
            #expect(Day(time, calendar: device) == day)
        }
    }

    @Test func isoAcceptsOnlyRealDates() {
        #expect(Day(iso: "2024-02-29") == Day(year: 2024, month: 2, day: 29))
        for text in [
            "2026-02-29", "2026-02-30", "2026-13-01", "2026-00-10", "2026-10-00", "2026-x-10-18", "2026-10", "", "2026-10-18T00:00",
            "2026--10-18", "2026-01-9223372036854775807", "9223372036854775807-01-01", "2026-9223372036854775807-01",
        ] {
            #expect(Day(iso: text) == nil, "\(text)")
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([Day].self, from: Data(#"["2026-02-30"]"#.utf8)) }
    }

    @Test func aCorruptTimestampDoesntTrap() {
        for seconds in [1e300, -1e300, .infinity, .nan] {
            #expect(Day(Date(timeIntervalSince1970: seconds), timeZone: .gmt) == Day(ordinal: 0))
        }
    }
}

@Suite("Units")
struct UnitTests {
    @Test func onlyTheUSDefaultsToPoundsAndInches() {
        #expect(UnitPreference.regional(for: Locale(identifier: "en_US")) == UnitPreference(weight: .lb, length: .inch))
        #expect(UnitPreference.regional(for: Locale(identifier: "en_GB")) == UnitPreference(weight: .kg, length: .cm))
        #expect(UnitPreference.regional(for: Locale(identifier: "fr_FR")) == UnitPreference(weight: .kg, length: .cm))
    }

    @Test func slopes() {
        #expect(leastSquaresSlope(x: [0, 1, 2, 3], y: [1, 3, 5, 7]) == 2)
        #expect(leastSquaresSlope(x: [2, 2, 2], y: [1, 3, 5]) == nil)
        #expect(leastSquaresSlope(x: [1], y: [1]) == nil)
        #expect(leastSquaresSlope(x: [1, 2], y: [1]) == nil)
        #expect([5.0, 4, 3].slope == -1)
        #expect([5.0].slope == nil)
    }
}

@Suite("Strength scoring")
struct StrengthScoringTests {
    @Test func anchorsAtReferenceBodyweight() {
        // A 100 kg bench at 80 kg bodyweight is 1.25 × BW: the intermediate anchor.
        let score = StrengthStandards.score(.horizontalPress, oneRepMaxKg: 100, bodyweightKg: 80, sex: .male)
        #expect(abs(score - 60) < 0.01)
        #expect(StrengthStandards.level(for: score) == "Intermediate")
        let inverse = StrengthStandards.oneRepMax(for: 60, .horizontalPress, bodyweightKg: 80, sex: .male)
        #expect(abs(inverse - 100) < 0.1)
    }

    @Test func heavierLiftersNeedASmallerMultiple() {
        let light = StrengthStandards.score(.squat, oneRepMaxKg: 140, bodyweightKg: 70, sex: .male)
        let heavy = StrengthStandards.score(.squat, oneRepMaxKg: 200, bodyweightKg: 100, sex: .male)
        // Both lift 2× bodyweight. Strength per kg falls as bodyweight rises, so the heavier
        // lifter's 2× is the bigger feat and scores higher.
        #expect(heavy > light)
        #expect(StrengthStandards.score(.squat, oneRepMaxKg: 0, bodyweightKg: 80, sex: .male) == 0)
    }

    @Test func imbalancePriorities() {
        let day = Day(year: 2026, month: 1, day: 1)
        let profile = StrengthProfile(
            categories: [
                CategoryScore(category: .squat, oneRepMaxKg: 160, score: 82, exerciseID: "a", day: day),
                CategoryScore(category: .floorPull, oneRepMaxKg: 190, score: 80, exerciseID: "b", day: day),
                CategoryScore(category: .horizontalPress, oneRepMaxKg: 80, score: 55, exerciseID: "c", day: day),
                CategoryScore(category: .verticalPull, oneRepMaxKg: 95, score: 52, exerciseID: "d", day: day),
                CategoryScore(category: .verticalPress, oneRepMaxKg: 50, score: 50, exerciseID: "e", day: day),
            ], bodyweightKg: 80, sex: .male)
        let priorities = profile.priorities
        #expect(priorities.contains { $0.target == .region(.upperPush) && $0.emphasis > 0 })
        #expect(priorities.contains { $0.target == .region(.lower) && $0.emphasis < 0 })
        #expect(profile.weakest?.category == .verticalPress)
        #expect(abs((profile.overall ?? 0) - 63.8) < 0.01)
    }

    @Test func eachPriorityAppearsOnce() {
        let day = Day(year: 2026, month: 1, day: 1)
        // Legs ahead of upper body and pressing ahead of pulling: both rules ask for more pulling.
        let profile = StrengthProfile(
            categories: [
                CategoryScore(category: .squat, oneRepMaxKg: 160, score: 80, exerciseID: "a", day: day),
                CategoryScore(category: .floorPull, oneRepMaxKg: 190, score: 80, exerciseID: "b", day: day),
                CategoryScore(category: .horizontalPress, oneRepMaxKg: 100, score: 70, exerciseID: "c", day: day),
                CategoryScore(category: .verticalPress, oneRepMaxKg: 60, score: 70, exerciseID: "d", day: day),
                CategoryScore(category: .verticalPull, oneRepMaxKg: 90, score: 55, exerciseID: "e", day: day),
                CategoryScore(category: .horizontalPull, oneRepMaxKg: 70, score: 55, exerciseID: "f", day: day),
            ], bodyweightKg: 80, sex: .male)
        let ids = profile.priorities.map(\.id)
        #expect(Set(ids).count == ids.count, "\(ids)")
        let pull = profile.priorities.first { $0.target == .region(.upperPull) }
        // The emphasis adds up as the generator would add it, and both reasons are kept.
        #expect(abs((pull?.emphasis ?? 0) - 1.7) < 1e-9)
        #expect(pull?.reason.contains("Legs are well ahead") == true && pull?.reason.contains("Pressing is ahead") == true)
    }

    @Test func ratioTablesCoverEveryCategory() {
        for category in StrengthCategory.allCases {
            for sex in [BiologicalSex.male, .female, .unspecified] {
                let table = StrengthStandards.ratios(category, sex)
                #expect(table.count == StrengthStandards.anchors.count && table == table.sorted())
            }
        }
    }

    @Test func estimatesWeighRatingsByTrust() {
        let set = LoggedSet(exerciseID: "x", kind: .working, loadKg: 100, reps: 5, rating: .green)
        let low = StrengthEstimator.estimate(set, basis: .external, trust: TrustState(prior: 0.1))!
        let high = StrengthEstimator.estimate(set, basis: .external, trust: TrustState(prior: 0.9))!
        let floor = OneRepMax.epley(100, reps: 5)
        #expect(low > floor && high > low)
        let repOut = LoggedSet(exerciseID: "x", kind: .repOut, loadKg: 100, reps: 8)
        #expect(StrengthEstimator.estimate(repOut, basis: .external, trust: TrustState(prior: 0.1)) == OneRepMax.epley(100, reps: 8))
        let warmup = LoggedSet(exerciseID: "x", kind: .warmup, loadKg: 60, reps: 5)
        #expect(StrengthEstimator.estimate(warmup, basis: .external, trust: TrustState(prior: 0.5)) == nil)
    }

    @Test func pullUpsCountTheBody() {
        let set = LoggedSet(exerciseID: "pull-up", kind: .repOut, loadKg: 10, reps: 5, bodyweightKg: 80)
        #expect(StrengthEstimator.estimate(set, basis: .bodyweightPlus, trust: TrustState(prior: 0.5)) == OneRepMax.epley(90, reps: 5))
        #expect(OneRepMax.effectiveLoad(20, basis: .assisted, bodyweightKg: 80) == 60)
    }
}

@Suite("Trust calibration")
struct TrustTests {
    @Test func repOutRevealsSandbagging() {
        let date = Date()
        let sets = [
            LoggedSet(exerciseID: "machine-chest-press", date: date, kind: .working, loadKg: 50, reps: 8, rating: .orange),
            LoggedSet(exerciseID: "machine-chest-press", date: date, kind: .repOut, loadKg: 50, reps: 14),
        ]
        let observations = Calibration.observations(sets: sets, exercise: TestExercise.chestPress)
        #expect(observations.count == 1)
        #expect((observations.first?.error ?? 0) > 2)
        #expect(observations.first?.source == .repOut)
    }

    @Test func accurateRatingIsConfirmed() {
        let date = Date()
        let sets = [
            LoggedSet(exerciseID: "machine-chest-press", date: date, kind: .working, loadKg: 50, reps: 10, rating: .orange),
            LoggedSet(exerciseID: "machine-chest-press", date: date, kind: .repOut, loadKg: 50, reps: 11),
        ]
        let observations = Calibration.observations(sets: sets, exercise: TestExercise.chestPress)
        #expect(observations.map(\.error) == [0])
        var trust = TrustState(experience: .novice)
        let before = trust.score
        trust.record(observations)
        #expect(trust.score > before)
    }

    @Test func heavierLaterSetShowsMoreWasLeft() {
        let date = Date()
        let sets = [
            LoggedSet(exerciseID: "machine-chest-press", date: date, kind: .working, loadKg: 40, reps: 10, rating: .orange),
            LoggedSet(exerciseID: "machine-chest-press", date: date, kind: .working, loadKg: 55, reps: 10, rating: .orange),
        ]
        let observations = Calibration.observations(sets: sets, exercise: TestExercise.chestPress)
        #expect(observations.count == 1)
        #expect(observations.first?.source == .verification)
        #expect((observations.first?.error ?? 0) > 1)
    }

    @Test func overconfidenceLowersTrust() {
        var trust = TrustState(experience: .experienced)
        let start = trust.score
        let day = Day(year: 2026, month: 1, day: 1)
        trust.record(
            (0..<8).map { _ in
                CalibrationObservation(day: day, exerciseID: "x", rating: .green, error: -3, source: .repOut, tier: .safeToFail)
            })
        #expect(trust.score < start - 0.2)
        #expect(trust.bias < -1)
        #expect(trust.reserve(for: .green) < SetRating.green.nominalRIR)
    }

    @Test func freeWeightEvidenceCountsLess() {
        let day = Day(year: 2026, month: 1, day: 1)
        var machine = TrustState(prior: 0.5)
        var barbell = TrustState(prior: 0.5)
        machine.record([CalibrationObservation(day: day, exerciseID: "m", rating: .orange, error: 0, source: .repOut, tier: .safeToFail)])
        barbell.record([CalibrationObservation(day: day, exerciseID: "b", rating: .orange, error: 0, source: .repOut, tier: .failWithSetup)])
        #expect(machine.score > barbell.score)
    }
}

@Suite("Autoregulation")
struct AutoregulationTests {
    let context = Autoregulation.Context(
        exercise: TestExercise.chestPress, increments: FixedIncrements(stepKg: 5),
        trust: TrustState(prior: 0.8), repRange: RepRange(8, 12))
    let planned = SetPrescription(kind: .working, loadKg: 50, targetReps: 10, targetRIR: 2)

    @Test func greenBumps() {
        let done = LoggedSet(exerciseID: "machine-chest-press", kind: .working, loadKg: 50, reps: 10, rating: .green)
        let adjustment = Autoregulation.next(after: done, planned: planned, context: context)
        #expect(adjustment.kind == .bump)
        #expect((adjustment.next.loadKg ?? 0) > 50)
        #expect((adjustment.next.loadKg ?? 0) <= 60)
    }

    @Test func orangeHolds() {
        let done = LoggedSet(exerciseID: "machine-chest-press", kind: .working, loadKg: 50, reps: 10, rating: .orange)
        let adjustment = Autoregulation.next(after: done, planned: planned, context: context)
        #expect(adjustment.kind == .hold)
        #expect(adjustment.next.loadKg == 50)
    }

    @Test func orangeIsVerifiedWhenTrustIsLow() {
        var low = context
        low.trust = TrustState(prior: 0.2)
        let done = LoggedSet(exerciseID: "machine-chest-press", kind: .working, loadKg: 50, reps: 10, rating: .orange)
        let adjustment = Autoregulation.next(after: done, planned: planned, context: low)
        #expect(adjustment.kind == .verify)
        #expect(adjustment.next.loadKg == 55)
        low.verifiedAlready = true
        #expect(Autoregulation.next(after: done, planned: planned, context: low).kind == .hold)
        // Racked barbell lifts only with safeties set.
        var bench = low
        bench.exercise = TestExercise.bench
        bench.verifiedAlready = false
        #expect(Autoregulation.next(after: done, planned: planned, context: bench).kind == .hold)
        bench.hasSafeties = true
        #expect(Autoregulation.next(after: done, planned: planned, context: bench).kind == .verify)
    }

    @Test func redDrops() {
        let done = LoggedSet(exerciseID: "machine-chest-press", kind: .working, loadKg: 50, reps: 6, targetReps: 10, rating: .red)
        let adjustment = Autoregulation.next(after: done, planned: planned, context: context)
        #expect(adjustment.kind == .drop)
        #expect((adjustment.next.loadKg ?? 99) < 50)
        #expect(adjustment.message.contains("just data"))
    }

    @Test func findingWeightSettles() {
        let finding = SetPrescription(kind: .findingWeight, loadKg: nil, targetReps: 10, targetRIR: 2)
        let easy = LoggedSet(exerciseID: "machine-chest-press", kind: .findingWeight, loadKg: 30, reps: 10, rating: .green)
        let up = Autoregulation.next(after: easy, planned: finding, context: context)
        #expect(up.next.kind == .findingWeight)
        #expect((up.next.loadKg ?? 0) >= 35)
        let right = LoggedSet(exerciseID: "machine-chest-press", kind: .findingWeight, loadKg: 45, reps: 10, rating: .orange)
        let found = Autoregulation.next(after: right, planned: finding, context: context)
        #expect(found.kind == .found)
        #expect(found.next.kind == .working)
        #expect(found.next.loadKg == 45)
        #expect(found.next.targetReps < 10, "the set after a just-right one expects a rep or so fewer")
    }

    /// 225 lb (102.5 kg) squats in a 5–8 range, with the 150 s the plan gives a heavy compound.
    let squat = Autoregulation.Context(
        exercise: TestExercise.squat, increments: FixedIncrements(stepKg: 2.5), trust: TrustState(prior: 0.8),
        repRange: RepRange(5, 8), restSeconds: 150)
    let squatSet = SetPrescription(kind: .working, loadKg: 102.5, targetReps: 8, targetRIR: 2)

    func squats(_ reps: Int, _ rating: SetRating) -> LoggedSet {
        LoggedSet(exerciseID: "barbell-back-squat", kind: .working, loadKg: 102.5, reps: reps, targetReps: 8, rating: rating)
    }

    @Test("Just right keeps the weight and aims for the reps the rest gives back, not the same again")
    func justRightExpectsRepsToFall() {
        let adjustment = Autoregulation.next(after: squats(8, .orange), planned: squatSet, context: squat)
        #expect(adjustment.kind == .hold)
        #expect(adjustment.next.loadKg == 102.5)
        #expect((6...7).contains(adjustment.next.targetReps), "\(adjustment.next.targetReps)")
        #expect(adjustment.message.contains("aim for \(adjustment.next.targetReps)"))
        #expect(adjustment.fatigue?.reps() == adjustment.next.targetReps)
        // A short rest leaves fewer reps; a long one gives more of them back.
        var short = squat
        short.restSeconds = 45
        #expect(Autoregulation.next(after: squats(8, .orange), planned: squatSet, context: short).next.targetReps < adjustment.next.targetReps)
        var long = squat
        long.restSeconds = 300
        #expect(Autoregulation.next(after: squats(8, .orange), planned: squatSet, context: long).next.targetReps > adjustment.next.targetReps)
    }

    @Test("A miss keeps the weight while the reps stay in the range, and comes down below it")
    func missHoldsInTheRange() {
        let held = Autoregulation.next(after: squats(7, .red), planned: squatSet, context: squat)
        #expect(held.kind == .hold)
        #expect(held.next.loadKg == 102.5)
        #expect(held.next.targetReps == 5)
        #expect(held.message.contains("just data"))
        let dropped = Autoregulation.next(after: squats(5, .red), planned: squatSet, context: squat)
        #expect(dropped.kind == .drop)
        #expect((dropped.next.loadKg ?? 999) < 102.5)
        #expect(dropped.next.targetReps == 5)
        #expect(dropped.fatigue == nil)
    }

    @Test("Just right at the bottom of the range lightens the next set to stay in it")
    func justRightAtTheBottomLightens() {
        let adjustment = Autoregulation.next(after: squats(5, .orange), planned: squatSet, context: squat)
        #expect(adjustment.kind == .drop)
        #expect((adjustment.next.loadKg ?? 999) < 102.5)
        #expect(adjustment.next.targetReps == 5)
        #expect(adjustment.message.contains("5–8"))
    }

    @Test("A check on a just-right set asks for the reps the rest gives back, one step up")
    func verificationAllowsForFatigue() {
        var low = squat
        low.trust = TrustState(prior: 0.2)
        low.hasSafeties = true
        let adjustment = Autoregulation.next(after: squats(8, .orange), planned: squatSet, context: low)
        #expect(adjustment.kind == .verify)
        #expect(adjustment.next.loadKg == 105)
        #expect(adjustment.next.targetReps < 8)
    }

    @Test("A shorter rest than planned works the next set out again")
    func shorterRestLowersTheTarget() throws {
        let basis = try #require(Autoregulation.next(after: squats(8, .orange), planned: squatSet, context: squat).fatigue)
        #expect(basis.reps(restSeconds: 45) < basis.reps())
        #expect(basis.reps(restSeconds: 300) >= basis.reps())
        // The set after carries on as if this one comes out as aimed.
        #expect(basis.following.reps() <= basis.reps())
        #expect(basis.following.capacity == Double(basis.reps()) + basis.aim)
    }

    @Test func assistedGetsHarderByRemovingAssistance() {
        var assisted = TestExercise.pullUp
        assisted.loadBasis = .assisted
        let ctx = Autoregulation.Context(
            exercise: assisted, increments: FixedIncrements(stepKg: 5), trust: TrustState(prior: 0.8),
            repRange: RepRange(6, 10))
        let done = LoggedSet(exerciseID: "pull-up", kind: .working, loadKg: 30, reps: 8, rating: .green, bodyweightKg: 80)
        let adjustment = Autoregulation.next(
            after: done, planned: SetPrescription(kind: .working, loadKg: 30, targetReps: 8, targetRIR: 2), context: ctx)
        #expect((adjustment.next.loadKg ?? 99) < 30)
    }
}

@Suite("Progression")
struct ProgressionTests {
    @Test func firstTimeFindsAWeight() {
        let context = ProgressionContext(
            exercise: TestExercise.chestPress, increments: FixedIncrements(stepKg: 5), trust: TrustState(prior: 0.3),
            phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: [])
        let p = Progression.prescribe(SlotTarget(sets: 3, repRange: RepRange(8, 12), targetRIR: 2), context)
        #expect(p.mode == .findingWeight)
        #expect(p.sets.allSatisfy { $0.loadKg == nil && $0.targetReps == 10 })
        // At the middle of the range, where the sessions after aim: not 10 whatever the range.
        for (range, reps) in [(RepRange(3, 6), 5), (RepRange(5, 8), 7), (RepRange(6, 10), 8), (RepRange(10, 15), 13), (RepRange(12, 20), 16)] {
            let finding = Progression.prescribe(SlotTarget(sets: 3, repRange: range, targetRIR: 2), context)
            #expect(finding.sets.allSatisfy { $0.targetReps == reps }, "\(range.label)")
            #expect(finding.reason.contains("for \(reps)"))
        }
    }

    @Test("A block's first week comes down to its target, not within a step of the last block's heaviest")
    func aBlocksFirstWeekStartsLighter() {
        // The end of a strength block: bench 100 × 5, just right.
        let history = (0..<3).map { index in
            LoggedSet(
                exerciseID: "barbell-bench-press", date: Self.night.addingTimeInterval(Double(index) * 180), kind: .working, loadKg: 100,
                reps: 5, rating: .orange, restBeforeSeconds: index == 0 ? nil : 180)
        }
        // A size block's first week: 6–10 reps, aiming for 8 with 3 in reserve, about 88 kg.
        let size = SlotTarget(sets: 3, repRange: RepRange(6, 10), targetRIR: 3, firstWeek: true)
        let first = Progression.prescribe(size, context(.bench, step: 2.5, history: history))
        #expect(first.sets.allSatisfy { $0.targetReps == 8 })
        let load = first.sets.first?.loadKg ?? 0
        #expect(load > 80 && load <= 90, "\(load)")
        // Later in a block the same session is an off day at most, and the weight holds within a step.
        var later = size
        later.firstWeek = false
        #expect(Progression.prescribe(later, context(.bench, step: 2.5, history: history)).sets.allSatisfy { $0.loadKg == 97.5 })
    }

    @Test func deloadHalvesSetsAndLightens() {
        let date = Date()
        let history = (0..<3).map { _ in
            LoggedSet(exerciseID: "barbell-bench-press", date: date, kind: .working, loadKg: 100, reps: 6, rating: .orange)
        }
        let context = ProgressionContext(
            exercise: TestExercise.bench, increments: FixedIncrements(stepKg: 2.5), trust: TrustState(prior: 0.6),
            phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: history)
        let p = Progression.prescribe(SlotTarget(sets: 4, repRange: RepRange(5, 8), targetRIR: 1, deload: true), context)
        #expect(p.mode == .deload)
        #expect(p.sets.count == 2)
        #expect(p.sets.allSatisfy { ($0.loadKg ?? 999) < 100 })
    }

    @Test func coarseIncrementsClimbReps() {
        let date = Date()
        let history = (0..<3).map { _ in LoggedSet(exerciseID: "db", date: date, kind: .working, loadKg: 10, reps: 10, rating: .orange) }
        var exercise = TestExercise.chestPress
        exercise.equipment = .dumbbell
        exercise.loadBasis = .perHand
        let context = ProgressionContext(
            exercise: exercise, increments: FixedIncrements(stepKg: 2), trust: TrustState(prior: 0.6),
            phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: history)
        let p = Progression.prescribe(SlotTarget(sets: 3, repRange: RepRange(8, 12), targetRIR: 2), context)
        #expect(p.mode == .reps)
        #expect(p.sets.first?.targetReps == 11)
        #expect(p.sets.first?.loadKg == 10)
    }

    @Test func injuryRampLightensTheLoad() {
        let date = Date()
        let history = (0..<3).map { _ in
            LoggedSet(exerciseID: "barbell-bench-press", date: date, kind: .working, loadKg: 100, reps: 6, rating: .orange)
        }
        let full = ProgressionContext(
            exercise: TestExercise.bench, increments: FixedIncrements(stepKg: 2.5), trust: TrustState(prior: 0.6),
            phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 80, history: history)
        var ramp = full
        ramp.loadFactor = 0.7
        let target = SlotTarget(sets: 3, repRange: RepRange(5, 8), targetRIR: 2)
        #expect((Progression.prescribe(target, ramp).sets.first?.loadKg ?? 999) < (Progression.prescribe(target, full).sets.first?.loadKg ?? 0))
    }

    @Test("Reps falling set to set as fatigue says aren't misses that hold progression back")
    func fatigueIsNotAMiss() {
        func session(_ sets: [(Int, SetRating)]) -> [LoggedSet] {
            sets.enumerated().map { index, set in
                LoggedSet(
                    exerciseID: "barbell-back-squat", date: Self.night.addingTimeInterval(Double(index) * 180), kind: .working,
                    loadKg: 102.5, reps: set.0, targetReps: 8, rating: set.1, restBeforeSeconds: index == 0 ? nil : 180)
            }
        }
        let trust = TrustState(prior: 0.8)
        let fatigue = session([(8, .orange), (7, .red), (6, .red)])
        #expect(Progression.shortfalls(fatigue, at: 102.5, exercise: TestExercise.squat, trust: trust) == 0)
        let short = session([(8, .orange), (5, .red), (2, .red)])
        #expect(Progression.shortfalls(short, at: 102.5, exercise: TestExercise.squat, trust: trust) == 2)
    }

    @Test func rirFallsAcrossTheBlock() {
        #expect(Progression.targetRIR(week: 0, of: 5) == 3)
        #expect(Progression.targetRIR(week: 4, of: 5) == 0.5)
        #expect(Progression.targetRIR(week: 2, of: 5) > Progression.targetRIR(week: 3, of: 5))
    }

    /// Midnight on a fixed summer day, in this machine's time zone (sets are grouped by its days).
    static let night = Day(year: 2026, month: 6, day: 10).date()

    func context(_ exercise: TestExercise, step: Double, history: [LoggedSet], loadFactor: Double = 1) -> ProgressionContext {
        ProgressionContext(
            exercise: exercise, increments: FixedIncrements(stepKg: step), trust: TrustState(prior: 0.6),
            phase: NutritionPhase.assumedMaintenance.effects, loadFactor: loadFactor, bodyweightKg: 80, history: history)
    }

    @Test(arguments: [0.6, 0.92])
    func aDeloadDuringARampScalesTheEffectiveLoad(_ factor: Double) {
        let deload = SlotTarget(sets: 4, repRange: RepRange(5, 8), targetRIR: 1, deload: true)
        // External: 87.5 kg last time, so at most 87.5 × 0.88 × the factor, on the gym's 2.5 kg steps.
        let bench = (0..<3).map { _ in
            LoggedSet(exerciseID: "barbell-bench-press", date: Self.night, kind: .working, loadKg: 87.5, reps: 6, rating: .orange)
        }
        for set in Progression.prescribe(deload, context(.bench, step: 2.5, history: bench, loadFactor: factor)).sets {
            let load = set.loadKg ?? 0
            #expect(load <= 87.5 * 0.88 * factor && load > 0)
            #expect(abs(load / 2.5 - (load / 2.5).rounded()) < 1e-9, "\(load) kg isn't on 2.5 kg steps")
        }
        // Assisted: 20 kg of help at 80 kg is 60 kg lifted. Easing in means more help, never less.
        var assisted = TestExercise.pullUp
        assisted.loadBasis = .assisted
        let pullUps = (0..<3).map { _ in
            LoggedSet(exerciseID: "pull-up", date: Self.night, kind: .working, loadKg: 20, reps: 8, rating: .orange, bodyweightKg: 80)
        }
        for set in Progression.prescribe(deload, context(assisted, step: 2.5, history: pullUps, loadFactor: factor)).sets {
            let help = set.loadKg ?? 0
            #expect(help > 20)
            #expect(80 - help <= 60 * 0.88 * factor)
        }
    }

    @Test func noRepOutWhileALiftRampsBack() {
        let history = (0..<3).map { _ in
            LoggedSet(exerciseID: "leg-extension", date: Self.night, kind: .working, loadKg: 60, reps: 12, rating: .orange)
        }
        let checkIn = SlotTarget(sets: 3, repRange: RepRange(10, 15), targetRIR: 1, deload: true, repOut: true)
        // Fresh: the check-in's last set goes to failure at the last working weight.
        let fresh = Progression.prescribe(checkIn, context(.legExtension, step: 5, history: history))
        #expect(fresh.sets.last?.kind == .repOut && fresh.sets.last?.loadKg == 60)
        // A knee ramping back at 69%: every set stays light and short of failure.
        let ramping = Progression.prescribe(checkIn, context(.legExtension, step: 5, history: history, loadFactor: 0.69))
        #expect(ramping.sets.allSatisfy { $0.kind == .deload && ($0.loadKg ?? 99) < 60 && $0.targetRIR > 0 })
        #expect(!ramping.reason.contains("Last set"))
        // The same in a loading week on coarse dumbbell steps, where reps are trimmed instead.
        var dumbbell = TestExercise.chestPress
        dumbbell.equipment = .dumbbell
        dumbbell.loadBasis = .perHand
        let db = (0..<3).map { _ in LoggedSet(exerciseID: "db", date: Self.night, kind: .working, loadKg: 10, reps: 10, rating: .orange) }
        let loading = SlotTarget(sets: 3, repRange: RepRange(8, 12), targetRIR: 2, repOut: true)
        #expect(Progression.prescribe(loading, context(dumbbell, step: 2, history: db)).sets.last?.kind == .repOut)
        #expect(!Progression.prescribe(loading, context(dumbbell, step: 2, history: db, loadFactor: 0.7)).sets.contains { $0.kind == .repOut })
    }

    @Test func aWorkoutPastMidnightIsOneSession() {
        // Two sets just before midnight, then a third, fatigued, just after it.
        let history = [
            LoggedSet(
                exerciseID: "barbell-bench-press", date: Self.night.addingTimeInterval(-10 * 60), kind: .working, loadKg: 100, reps: 6,
                rating: .orange),
            LoggedSet(
                exerciseID: "barbell-bench-press", date: Self.night.addingTimeInterval(-4 * 60), kind: .working, loadKg: 100, reps: 6, rating: .orange
            ),
            LoggedSet(
                exerciseID: "barbell-bench-press", date: Self.night.addingTimeInterval(3 * 60), kind: .working, loadKg: 100, reps: 4, targetReps: 6,
                rating: .red),
        ]
        #expect(StrengthEstimator.sessions(history).count == 1)
        #expect(
            StrengthEstimator.sessionBests(history, basis: .external, trust: TrustState(prior: 0.6)).map(\.day) == [Day(year: 2026, month: 6, day: 9)]
        )
        // One red set at the end isn't a miss, so the one-step floor holds: 97.5, not 90.
        let p = Progression.prescribe(SlotTarget(sets: 3, repRange: RepRange(5, 8), targetRIR: 2), context(.bench, step: 2.5, history: history))
        #expect(p.mode == .load)
        #expect(p.sets.allSatisfy { ($0.loadKg ?? 0) >= 97.5 })
        // Sessions further apart than three hours are separate, even on one day.
        let twoADay = [
            history[0],
            LoggedSet(
                exerciseID: "barbell-bench-press", date: Self.night.addingTimeInterval(-6 * 3600), kind: .working, loadKg: 90,
                reps: 6, rating: .orange),
        ]
        #expect(StrengthEstimator.sessions(twoADay).map { $0.map(\.loadKg) } == [[90], [100]])
    }

    @Test func aStallPromptBuildsOnTheLastRealSessionNotTheDeload() {
        // Bench stuck at 100 × 5 for five weeks, then a deload session at 87.5.
        let start = Day(year: 2026, month: 3, day: 2)
        var history = stride(from: 0, through: 32, by: 4).flatMap { offset in
            (0..<3).map { _ in
                LoggedSet(
                    exerciseID: "barbell-bench-press", date: start.adding(days: offset).date().addingTimeInterval(18 * 3600), kind: .working,
                    loadKg: 100, reps: 5, rating: .orange)
            }
        }
        history += (0..<2).map { _ in
            LoggedSet(
                exerciseID: "barbell-bench-press", date: start.adding(days: 35).date().addingTimeInterval(18 * 3600), kind: .deload, loadKg: 87.5,
                reps: 5, rating: .green)
        }
        let report = Stalls.detect(
            context(.bench, step: 2.5, history: history), sets: 3, repRange: RepRange(5, 8), today: start.adding(days: 36),
            phase: NutritionPhase.assumedMaintenance.effects, beatUp: false)
        #expect(report?.reading == .programming)
        #expect(report?.suggestion?.loadKg == 102.5)
    }
}

@Suite("Blocks and life modes")
struct ScheduleTests {
    let start = Day(year: 2026, month: 3, day: 2)

    @Test func blockLengthByContext() {
        #expect(BlockScheduler.loadingWeeks(phase: NutritionPhase.assumedMaintenance.effects, experience: .intermediate) == 5)
        #expect(BlockScheduler.loadingWeeks(phase: NutritionPhase(kind: .cut, source: .macroTrack).effects, experience: .intermediate) == 4)
        #expect(BlockScheduler.loadingWeeks(phase: NutritionPhase(kind: .miniCut, source: .macroTrack).effects, experience: .intermediate) == 3)
        #expect(BlockScheduler.loadingWeeks(phase: NutritionPhase(kind: .leanBulk, source: .macroTrack).effects, experience: .novice) == 7)
    }

    @Test func vacationNearTheDeloadBecomesIt() {
        let block = TrainingBlock(kind: .standard, start: start, loadingWeeks: 5)
        let vacation = DayRange(start.adding(days: 30), start.adding(days: 38))
        let reflowed = BlockScheduler.reflow(block, vacations: [vacation])
        #expect(reflowed.effectiveDeloadStart == vacation.start)
        #expect(reflowed.end == vacation.end)
        #expect(reflowed.deloadReason?.contains("becomes the deload") == true)
        #expect(reflowed.week(of: start.adding(days: 31)) == .deload)
    }

    @Test func earlyVacationCutsTheBlockShort() {
        let block = TrainingBlock(kind: .standard, start: start, loadingWeeks: 5)
        let vacation = DayRange(start.adding(days: 10), start.adding(days: 16))
        let reflowed = BlockScheduler.reflow(block, vacations: [vacation])
        #expect(reflowed.end == vacation.end)
        #expect(reflowed.deloadReason?.contains("fresh block") == true)
    }

    @Test func vacationInTheFirstDaysMovesTheStart() {
        let block = TrainingBlock(kind: .standard, start: start, loadingWeeks: 5)
        let vacation = DayRange(start.adding(days: 1), start.adding(days: 7))
        let reflowed = BlockScheduler.reflow(block, vacations: [vacation])
        #expect(reflowed.start == start.adding(days: 8))
        #expect(reflowed.loadingWeeks == 5)
    }

    @Test(arguments: [(2, 4), (5, 6), (0, 8)])
    func aVacationThatStartsInTheDeloadKeepsIt(_ startsAfter: Int, _ lasts: Int) {
        let block = TrainingBlock(kind: .standard, start: start, loadingWeeks: 5)
        let vacation = DayRange(block.plannedDeloadStart.adding(days: startsAfter), block.plannedDeloadStart.adding(days: startsAfter + lasts))
        let reflowed = BlockScheduler.reflow(block, vacations: [vacation])
        // The deload days stay deload days; they don't turn back into the last, hardest loading week.
        #expect(reflowed.effectiveDeloadStart == block.plannedDeloadStart)
        #expect(reflowed.week(of: block.plannedDeloadStart) == .deload)
        #expect(reflowed.week(of: block.plannedDeloadStart.adding(days: -1)) == .loading(4))
        #expect(reflowed.end == max(block.end, vacation.end))
        #expect(BlockScheduler.calendar(blocks: [reflowed], today: start).deloads.first == DayRange(block.plannedDeloadStart, reflowed.end))
        #expect((reflowed.end > block.end) == (reflowed.deloadReason?.contains("runs through the trip") == true))
    }

    @Test func aTripDuringAnEarlyDeloadStretchesIt() {
        let fatigue = FatigueAssessment(
            status: .overreached, loadRatio: 1.6, acute: 10, chronic: 6, signals: ["Sleep is short."],
            action: .deloadEarly, budgetFactor: 0.7)
        let early = BlockScheduler.deloadEarly(
            TrainingBlock(kind: .standard, start: start, loadingWeeks: 5), today: start.adding(days: 17),
            fatigue: fatigue)!
        let reflowed = BlockScheduler.reflow(early, vacations: [DayRange(start.adding(days: 20), start.adding(days: 30))])
        #expect(reflowed.effectiveDeloadStart == start.adding(days: 17))
        #expect(reflowed.end == start.adding(days: 30))
        // Two overlapping trips near the deload: the first becomes it, the second stretches it.
        let block = TrainingBlock(kind: .standard, start: start, loadingWeeks: 5)
        let both = BlockScheduler.reflow(
            block,
            vacations: [
                DayRange(start.adding(days: 36), start.adding(days: 45)),
                DayRange(start.adding(days: 30), start.adding(days: 38)),
            ])
        #expect(both.effectiveDeloadStart == start.adding(days: 30))
        #expect(both.end == start.adding(days: 45))
    }

    @Test func shortTripsDontReshape() {
        let block = TrainingBlock(kind: .standard, start: start, loadingWeeks: 5)
        let reflowed = BlockScheduler.reflow(block, vacations: [DayRange(start.adding(days: 12), start.adding(days: 13))])
        #expect(reflowed == block)
    }

    @Test func earlyDeloadFromFatigue() {
        let block = TrainingBlock(kind: .standard, start: start, loadingWeeks: 5)
        let fatigue = FatigueAssessment(
            status: .overreached, loadRatio: 1.6, acute: 10, chronic: 6, signals: ["Sleep is short."],
            action: .deloadEarly, budgetFactor: 0.7)
        #expect(BlockScheduler.deloadEarly(block, today: start.adding(days: 8), fatigue: fatigue) == nil)
        let moved = BlockScheduler.deloadEarly(block, today: start.adding(days: 17), fatigue: fatigue)
        #expect(moved?.effectiveDeloadStart == start.adding(days: 17))
        #expect(moved?.checkInDay == start.adding(days: 23))
    }

    @Test func lifeModeEffects() {
        let vacation = LifeModePeriod(kind: .vacation, start: start, end: start.adding(days: 6), createdBy: .liftTrack)
        let during = LifeModes.effects(on: start.adding(days: 2), periods: [vacation])
        #expect(!during.trainingExpected && during.disciplineExempt)
        let after = LifeModes.effects(on: start.adding(days: 9), periods: [vacation])
        #expect(after.reentry && after.trainingExpected && !after.disciplineExempt)

        let crunch = LifeModePeriod(
            kind: .crunch(CrunchDials(minutesAvailable: 20, equipment: .hotelGym)), start: start,
            end: start.adding(days: 10), createdBy: .macroTrack)
        let c = LifeModes.effects(on: start.adding(days: 1), periods: [crunch])
        #expect(c.minimumEffectiveDose && c.maxMinutes == 20 && c.equipment == .hotelGym && !c.disciplineExempt && c.lifeStress > 0)

        let cold = LifeModePeriod(kind: .illness(.aboveNeck), start: start, createdBy: .liftTrack)
        let i = LifeModes.effects(on: start.adding(days: 3), periods: [cold])
        #expect(i.lightOnly && i.trainingExpected && i.disciplineExempt)
        let flu = LifeModePeriod(kind: .illness(.systemic), start: start, createdBy: .liftTrack)
        #expect(!LifeModes.effects(on: start, periods: [flu]).trainingExpected)
    }

    @Test func injuryFiltersAndRamps() {
        let injury = Injury(parts: [InjuredPart(.shoulder, side: .right)], severity: .moderate)
        #expect(injury.excludes(TestExercise.bench))
        #expect(injury.excludes(TestExercise.chestPress))
        #expect(!injury.excludes(TestExercise.legExtension))
        var allowed = injury
        allowed.allowed = [TestExercise.chestPress.id]
        #expect(!allowed.excludes(TestExercise.chestPress))
        #expect(!Injury(parts: [InjuredPart(.shoulder)], severity: .mild).excludes(TestExercise.chestPress))

        let period = LifeModePeriod(kind: .injury(injury), start: start, end: start.adding(days: 20), createdBy: .liftTrack)
        #expect(LifeModes.effects(on: start.adding(days: 5), periods: [period]).excludes(TestExercise.bench))
        let ramp = LifeModes.effects(on: start.adding(days: 25), periods: [period])
        #expect(!ramp.excludes(TestExercise.bench))
        let factor = ramp.loadFactor(for: TestExercise.bench)
        #expect(factor > 0.6 && factor < 1)
        #expect(ramp.loadFactor(for: TestExercise.legExtension) == 1)
    }

    @Test func overridesToggleBetweenAllowedAndSetAside() {
        var injury = Injury(parts: [InjuredPart(.shoulder, side: .right)], severity: .moderate)
        let press = TestExercise.chestPress
        // Set aside by the filter: a tap allows it, the next sets it aside by hand.
        injury.toggleOverride(for: press)
        #expect(!injury.excludes(press) && injury.allowed == [press.id] && injury.removed.isEmpty)
        injury.toggleOverride(for: press)
        #expect(injury.excludes(press) && injury.allowed.isEmpty && injury.removed == [press.id])
        // Allowed by the filter: set aside, allowed, set aside again.
        let extensions = TestExercise.legExtension
        injury.toggleOverride(for: extensions.id, currentlyExcluded: injury.excludes(extensions))
        #expect(injury.excludes(extensions) && injury.removed == [press.id, extensions.id])
        injury.toggleOverride(for: extensions.id, currentlyExcluded: injury.excludes(extensions))
        #expect(!injury.excludes(extensions) && injury.allowed == [extensions.id] && injury.removed == [press.id])
        injury.toggleOverride(for: extensions.id, currentlyExcluded: injury.excludes(extensions))
        #expect(injury.excludes(extensions) && injury.allowed.isEmpty && injury.removed == [press.id, extensions.id])
        // However many taps, each exercise is in one list, once.
        for _ in 0..<5 { injury.toggleOverride(for: press) }
        let all = injury.allowed + injury.removed
        #expect(all.count == Set(all).count && all.count == 2)
        // Lists that have it twice, or in both, come out with it in one.
        injury.allowed = [press.id, press.id]
        injury.removed.append(press.id)
        injury.toggleOverride(for: press.id, currentlyExcluded: false)
        #expect(injury.allowed.isEmpty && injury.removed == [extensions.id, press.id])
    }
}

@Suite("Discipline")
struct DisciplineTests {
    let today = Day(year: 2026, month: 5, day: 31)

    @Test func oneMissInFourWeeksIsInTheZone() {
        let window = Discipline.window(ending: today)
        var items = (0..<12).map { i in AdherenceItem(day: window.start.adding(days: i * 2), kind: .session, label: "Session", done: true) }
        items[3].done = false
        let score = Discipline.score(items, exempt: [], window: window)
        #expect(abs((score.rate ?? 0) - 11.0 / 12.0) < 0.001)
        #expect(score.band == .above)
        #expect(score.credit == 1)
        items[5].done = false
        items[7].done = false
        let lower = Discipline.score(items, exempt: [], window: window)
        #expect(lower.band == .below)
        #expect((lower.credit ?? 1) < 1)
    }

    @Test func exemptAndUnknownDaysDontCount() {
        let window = Discipline.window(ending: today)
        let items = [
            AdherenceItem(day: window.start, kind: .session, label: "S", done: false),
            AdherenceItem(day: window.start.adding(days: 1), kind: .mealLog, label: "M", done: nil),
            AdherenceItem(day: window.start.adding(days: 2), kind: .session, label: "S", done: true),
        ]
        let score = Discipline.score(items, exempt: [window.start], window: window)
        #expect(score.planned == 1 && score.completed == 1 && score.unknown == 1 && score.exemptDays == 1)
        #expect(score.rate == 1)
    }
}

@Suite("Fatigue Budget")
struct FatigueTests {
    let today = Day(year: 2026, month: 6, day: 30)

    func steadyEvents(days: Int = 28, systemic: Double = 4) -> [FatigueEvent] {
        stride(from: 0, to: days, by: 2).map { FatigueEvent(day: today.adding(days: -$0), load: FatigueLoad(systemic: systemic)) }
    }

    @Test func steadyTrainingIsProductive() {
        let assessment = FatigueBudget.assess(events: steadyEvents(), recovery: [], lifeStress: [:], performanceTrend: 0.01, today: today)
        #expect(assessment.status == .productive || assessment.status == .fresh)
        #expect(assessment.action == .none)
    }

    @Test func beatUpAndStalledReducesSystemicCost() {
        var events = steadyEvents()
        for i in events.indices where events[i].day > today.adding(days: -14) {
            events[i].feedback = SessionFeedback(soreness: 3, jointPain: [], energy: 2)
        }
        let recovery = (0..<7).map { RecoveryDay(day: today.adding(days: -$0), sleepHours: 7.5) }
        let assessment = FatigueBudget.assess(events: events, recovery: recovery, lifeStress: [:], performanceTrend: 0, today: today)
        #expect(assessment.status == .strained)
        #expect(assessment.action == .reduceSystemic)
    }

    @Test func stackedSignalsCallForAnEarlyDeload() {
        var events = steadyEvents()
        for i in events.indices where events[i].day > today.adding(days: -14) {
            events[i].feedback = SessionFeedback(soreness: 3, jointPain: [.knee], energy: 1)
        }
        let recovery = (0..<35).map { i in
            RecoveryDay(day: today.adding(days: -i), sleepHours: i < 7 ? 5.2 : 7.5, hrv: i < 7 ? 35 : 55, restingHeartRate: i < 7 ? 64 : 56)
        }
        let assessment = FatigueBudget.assess(events: events, recovery: recovery, lifeStress: [:], performanceTrend: -0.02, today: today)
        #expect(assessment.status == .overreached)
        #expect(assessment.action == .deloadEarly)
        #expect(assessment.budgetFactor < 1)
    }

    @Test func failureSetsCostMoreOnDeadlifts() {
        let normal = FatigueBudget.cost(
            of: LoggedSet(exerciseID: "d", kind: .working, loadKg: 150, reps: 5, rating: .orange), exercise: TestExercise.deadlift)
        let failed = FatigueBudget.cost(of: LoggedSet(exerciseID: "d", kind: .repOut, loadKg: 150, reps: 8), exercise: TestExercise.deadlift)
        #expect(failed.systemic > normal.systemic * 1.8)
    }

    @Test func outsideTrainingSpendsTheSameBudget() {
        let phase = NutritionPhase.assumedMaintenance.effects
        let none = FatigueBudget.weeklySystemicBudget(experience: .intermediate, daysPerWeek: 4, phase: phase, assessment: nil, outside: .zero)
        let bjj = ActivityLog(type: .bjj, start: Date(), minutes: 90, martialArts: MartialArtsDetails(classType: .sparring, sparringRounds: 6))
        let withBJJ = FatigueBudget.weeklySystemicBudget(
            experience: .intermediate, daysPerWeek: 4, phase: phase, assessment: nil,
            outside: bjj.fatigue + bjj.fatigue)
        #expect(withBJJ < none)
        #expect(withBJJ >= none * 0.45)
        let cut = FatigueBudget.weeklySystemicBudget(
            experience: .intermediate, daysPerWeek: 4,
            phase: NutritionPhase(kind: .cut, source: .selfReported).effects, assessment: nil, outside: .zero)
        #expect(cut < none)
    }
}

@Suite("Agility, physique, endurance")
struct StatsTests {
    @Test func weakestMobilityTestBecomesTheLimiter() {
        let day = Day(year: 2026, month: 1, day: 1)
        let analysis = Agility.analyse([
            MobilityResult(test: .kneeToWall, day: day, value: 11),
            MobilityResult(test: .hip9090, day: day, value: 1),
            MobilityResult(test: .sitAndReach, day: day, value: 2),
        ])
        #expect(analysis.limiter == .hips)
        #expect(analysis.limiterTest == .hip9090)
        let painful = Agility.analyse([MobilityResult(test: .overheadReach, day: day, value: 1, painful: true)])
        #expect(painful.seePhysio == [.overheadReach])
    }

    @Test func aTieGoesToTheFirstTestEveryTime() {
        let day = Day(year: 2026, month: 1, day: 1)
        // "Mostly clean" twice and a 40-second squat hold all score exactly two thirds.
        let results = [
            MobilityResult(test: .overheadReach, day: day, value: 2),
            MobilityResult(test: .deepSquatHold, day: day, value: 40),
            MobilityResult(test: .hip9090, day: day, value: 2),
            MobilityResult(test: .kneeToWall, day: day, value: 12),
        ]
        // Every order, each a fresh dictionary with its own iteration order: a pick that followed the
        // dictionary would land on another test in some of them.
        func permutations(_ list: [MobilityResult]) -> [[MobilityResult]] {
            list.count <= 1
                ? [list]
                : list.indices.flatMap { i in
                    var rest = list
                    let first = rest.remove(at: i)
                    return permutations(rest).map { [first] + $0 }
                }
        }
        for order in permutations(results) {
            let analysis = Agility.analyse(order)
            #expect(analysis.limiter == .hips)
            #expect(analysis.limiterTest == .hip9090)
        }
    }

    @Test func ffmiUsesTheCurrentWeightOverOneTypedLongAgo() {
        // 90 kg typed at onboarding, then tape only; Health says 80 kg now.
        let onboarding = BodyMeasurements(day: Day(year: 2026, month: 1, day: 1), weightKg: 90, neckCm: 39, waistCm: 88)
        let lately = BodyMeasurements(day: Day(year: 2026, month: 9, day: 1), neckCm: 39, waistCm: 84)
        let analysis = Physique.analyse([lately, onboarding], sex: .male, heightCm: 180, weightKg: 80)
        let bodyFat = Physique.tapeBodyFat(lately, sex: .male, heightCm: 180)!
        #expect(analysis.latest?.weightKg == 80)
        #expect(analysis.bodyFatSource == .tape && analysis.bodyFatPercent == bodyFat)
        #expect(analysis.ffmi == Physique.ffmi(weightKg: 80, bodyFatPercent: bodyFat, heightCm: 180)?.ffmi)
        #expect(analysis.direction.normalizedFFMI == analysis.normalizedFFMI)
        // With no current weight, the typed one still counts.
        #expect(Physique.analyse([lately, onboarding], sex: .male, heightCm: 180).latest?.weightKg == 90)
    }

    @Test func physiqueGapsSpeakInProportions() {
        let day = Day(year: 2026, month: 1, day: 1)
        let analysis = Physique.analyse(
            [BodyMeasurements(day: day, neckCm: 39, shouldersCm: 112, waistCm: 86, armCm: 36)],
            sex: .male, heightCm: 180)
        #expect(analysis.gaps.first?.region == .shoulders)
        #expect(analysis.bodyFatEstimated)
        #expect((analysis.bodyFatPercent ?? 0) > 10 && (analysis.bodyFatPercent ?? 100) < 25)
        #expect(analysis.gaps.allSatisfy { !$0.finding.lowercased().contains("fat") })
    }

    @Test func tapeBodyFatUsesEachSexsSites() {
        let day = Day(year: 2026, month: 1, day: 1)
        let m = BodyMeasurements(day: day, neckCm: 33, waistCm: 84, naturalWaistCm: 72, glutesCm: 100)
        #expect(
            Physique.tapeBodyFat(m, sex: .female, heightCm: 165)
                == Physique.navyBodyFat(sex: .female, heightCm: 165, neckCm: 33, waistCm: 72, hipsCm: 100))
        #expect(
            Physique.tapeBodyFat(m, sex: .male, heightCm: 180)
                == Physique.navyBodyFat(sex: .male, heightCm: 180, neckCm: 33, waistCm: 84, hipsCm: nil))
        // Women's estimate needs the glutes; men's doesn't.
        #expect(Physique.tapeBodyFat(BodyMeasurements(day: day, neckCm: 33, waistCm: 84), sex: .female, heightCm: 165) == nil)
    }

    @Test func ffmiComesFromTheBestBodyFatReading() {
        let m = BodyMeasurements(day: Day(year: 2026, month: 1, day: 1), weightKg: 80, bodyFatPercent: 15, neckCm: 39, waistCm: 84)
        // 80 kg at 15% and 1.80 m: 68 kg lean, an FFMI of 20.99, already at the reference height.
        let entered = Physique.analyse([m], sex: .male, heightCm: 180)
        #expect(entered.bodyFatSource == .entered)
        #expect(abs((entered.ffmi ?? 0) - 20.99) < 0.01)
        #expect(abs((entered.normalizedFFMI ?? 0) - (entered.ffmi ?? 1)) < 0.001)
        #expect(entered.ffmiBand == .lotsOfRoom)
        // A recent Health reading beats a typed one: 72 kg lean is 22.2.
        let health = Physique.analyse([m], sex: .male, heightCm: 180, measuredBodyFat: 10)
        #expect(health.bodyFatSource == .health && health.bodyFatPercent == 10)
        #expect(health.ffmiBand == .someRoom)
        var untyped = m
        untyped.bodyFatPercent = nil
        #expect(Physique.analyse([untyped], sex: .male, heightCm: 180).bodyFatSource == .tape)
        // Shorter people are adjusted up to the reference height.
        let short = Physique.analyse([m], sex: .male, heightCm: 170)
        #expect((short.normalizedFFMI ?? 0) > (short.ffmi ?? 0))
    }

    @Test func limbSizesUseTheBiggerSide() {
        let day = Day(year: 2026, month: 1, day: 1)
        let m = BodyMeasurements(day: day, armCm: 30, armLeftCm: 35, armRightCm: 37)
        #expect(m.size(.arm) == 37)
        #expect(BodyMeasurements(day: day, armCm: 30).size(.arm) == 30)
        #expect(m.sides(.thigh) == nil)
    }

    @Test func aWaistDrivenRatioAsksForFatLossNotVolume() {
        let day = Day(year: 2026, month: 1, day: 1)
        // Shoulders 124 over a waist of 88 is 1.41; at a lean 82.8 cm waist it's about 1.48, on target.
        let soft = Physique.analyse([BodyMeasurements(day: day, neckCm: 39, shouldersCm: 124, waistCm: 88)], sex: .male, heightCm: 180)
        let reading = soft.proportions.first { $0.rule == .shoulderToWaist }
        #expect(reading?.flagged == true && reading?.cause == .fat)
        #expect(soft.gaps.isEmpty)
        #expect(soft.direction.fatLoss > 0 && soft.direction.build == 0)
        // Already lean with the same ratio: training closes it.
        let lean = Physique.analyse([BodyMeasurements(day: day, neckCm: 39, shouldersCm: 112, waistCm: 80)], sex: .male, heightCm: 180)
        #expect(lean.proportions.first { $0.rule == .shoulderToWaist }?.cause == .build)
        #expect(lean.gaps.first?.region == .shoulders)
        #expect(lean.direction.build > 0 && lean.direction.buildRegions == [.shoulders] && lean.direction.fatLoss == 0)
    }

    @Test func nothingAsksForFatLossAtTheFloor() {
        let day = Day(year: 2026, month: 1, day: 1)
        // The waist-driven body from above, but measured at 9% body fat: the waist isn't fat.
        let m = BodyMeasurements(day: day, bodyFatPercent: 9, neckCm: 39, shouldersCm: 124, waistCm: 88)
        let analysis = Physique.analyse([m], sex: .male, heightCm: 180)
        #expect(analysis.direction.atLeanFloor)
        #expect(analysis.direction.fatLoss == 0)
        #expect(analysis.proportions.first { $0.rule == .shoulderToWaist }?.cause == .build)
        #expect(Proportions.atLeanFloor(bodyFatPercent: 20, waistToHeight: nil, sex: .female))
        #expect(!Proportions.atLeanFloor(bodyFatPercent: 21, waistToHeight: nil, sex: .female))
        #expect(Proportions.atLeanFloor(bodyFatPercent: nil, waistToHeight: 0.42, sex: .male))
    }

    @Test func hourglassTellsWaistFromGlutes() {
        let day = Day(year: 2026, month: 1, day: 1)
        // Waist 76 over glutes 98 is 0.78; at a lean waist the glutes shrink half as fast and it's about 0.75.
        let soft = Physique.analyse(
            [BodyMeasurements(day: day, shouldersCm: 100, waistCm: 82, naturalWaistCm: 76, glutesCm: 98)],
            sex: .female, heightCm: 165)
        #expect(soft.targets == .hourglass)
        #expect(soft.proportions.first { $0.rule == .waistToGlutes }?.cause == .fat)
        // Lean, with the glutes behind: build them.
        let lean = Physique.analyse(
            [BodyMeasurements(day: day, shouldersCm: 94, waistCm: 74, naturalWaistCm: 70, glutesCm: 88)],
            sex: .female, heightCm: 165)
        #expect(lean.proportions.first { $0.rule == .waistToGlutes }?.cause == .build)
        #expect(lean.gaps.contains { $0.region == .glutes })
    }

    @Test func eachTargetSetChecksItsOwnRules() {
        #expect(ProportionTargets.standard(for: .male) == .vTaper)
        #expect(ProportionTargets.standard(for: .female) == .hourglass)
        #expect(ProportionTargets.standard(for: .unspecified) == .leannessOnly)
        #expect(ProportionTargets.vTaper.rules(sex: .male).contains(.chestToWaist))
        #expect(!ProportionTargets.vTaper.rules(sex: .female).contains(.chestToWaist))
        #expect(ProportionTargets.leannessOnly.rules(sex: .male) == [.thighToCalf])
        #expect(ProportionTargets.off.rules(sex: .female).isEmpty)
        let m = BodyMeasurements(day: Day(year: 2026, month: 1, day: 1), neckCm: 39, shouldersCm: 112, waistCm: 80)
        #expect(Physique.analyse([m], sex: .male, heightCm: 180, targets: .off).gaps.isEmpty)
        // A health ratio only ever asks for fat loss.
        let wide = Physique.analyse(
            [BodyMeasurements(day: Day(year: 2026, month: 1, day: 1), waistCm: 100, glutesCm: 105)],
            sex: .male, heightCm: 180)
        let health = wide.proportions.first { $0.rule == .waistToHips }
        #expect(health?.cause == .fat && health?.region == nil)
    }

    @Test func aSideCountsAsLaggingOnlyWhenItLasts() {
        let start = Day(year: 2026, month: 1, day: 1)
        func check(_ offset: Int, _ left: Double, _ right: Double) -> BodyMeasurements {
            BodyMeasurements(day: start.adding(days: offset), armLeftCm: left, armRightCm: right)
        }
        // One reading apart is noise, and so are two within a fortnight.
        #expect(Physique.asymmetries([check(0, 35, 37)]).isEmpty)
        #expect(Physique.asymmetries([check(0, 35, 37), check(7, 35.1, 37)]).isEmpty)
        // Apart at two check-ins two weeks apart: the left arm lags.
        let lagging = Physique.asymmetries([check(0, 35, 37), check(14, 35.2, 37.1)])
        #expect(lagging.first?.limb == .arm && lagging.first?.smaller == .left)
        #expect(lagging.first.map { $0.magnitude > 0 && $0.magnitude < 1 } == true)
        // Once flagged it holds while the sides are more than a centimetre apart, and clears inside one.
        #expect(Physique.asymmetries([check(0, 35, 37), check(14, 35.2, 37.1), check(28, 35.9, 37.1)]).count == 1)
        #expect(Physique.asymmetries([check(0, 35, 37), check(14, 35.2, 37.1), check(42, 36.6, 37.1)]).isEmpty)
        // A centimetre either way is normal.
        #expect(Physique.asymmetries([check(0, 36, 37), check(14, 36, 37)]).isEmpty)
        // Readings with no side never count.
        #expect(Physique.asymmetries([BodyMeasurements(day: start, armCm: 35), BodyMeasurements(day: start.adding(days: 20), armCm: 35)]).isEmpty)
    }

    @Test func restKeepsMinimumsForHeavyCompounds() {
        let heavy = Rest.plan(role: .heavyCompound, reps: 5, defaultSeconds: 180, enduranceScore: 70, hrGuidance: true)
        #expect(!heavy.heartRateGuided && heavy.minimum >= 150)
        let accessory = Rest.plan(role: .accessory, reps: 12, defaultSeconds: 75, enduranceScore: 30, hrGuidance: true)
        #expect(accessory.heartRateGuided && accessory.target > 75)
        let zones = HeartRateZones(resting: 60, maximum: 190)
        #expect(!Rest.recovered(heartRate: 100, preSet: 95, zones: zones, elapsed: 30, plan: accessory))
        #expect(Rest.recovered(heartRate: 105, preSet: 95, zones: zones, elapsed: 50, plan: accessory))
        #expect(!Rest.recovered(heartRate: 150, preSet: 95, zones: zones, elapsed: 80, plan: accessory))
    }

    @Test func heartRateRecoveryDrop() {
        let end = Date()
        let samples: [(date: Date, bpm: Double)] = [(end, 150), (end.addingTimeInterval(30), 130), (end.addingTimeInterval(60), 112)]
        let result = HeartRateRecovery.drop(samples: samples, setEnd: end)
        #expect(result?.peak == 150 && result?.drop == 38)
    }

    @Test func benchmarkImprovementDirection() {
        #expect(EnduranceBenchmark.row2k.improvement(from: 480, to: 470) > 0)
        #expect(EnduranceBenchmark.bike12min.improvement(from: 6000, to: 6200) > 0)
    }
}

@Suite("Quests and trajectories")
struct HubTests {
    @Test func questsAreCappedAndSpread() {
        let day = Day(year: 2026, month: 1, day: 1)
        let quests = [
            Quest(id: "a", title: "A", stat: .agility, source: .liftTrack, day: day, priority: 5),
            Quest(id: "b", title: "B", stat: .agility, source: .liftTrack, day: day, priority: 4),
            Quest(id: "c", title: "C", stat: .endurance, source: .liftTrack, day: day, priority: 3),
            Quest(id: "d", title: "D", stat: .vitality, source: .macroTrack, day: day, priority: 2),
            Quest(id: "e", title: "E", stat: .strength, source: .liftTrack, day: day, priority: 1),
        ]
        #expect(Quests.forDay(day, from: quests).map(\.id) == ["a", "c", "d"])
    }

    @Test func trajectoryReadsTheTrend() {
        let start = Day(year: 2026, month: 1, day: 1)
        let goal = TargetGoal(
            stat: .strength, title: "Bench 100", metric: "category:horizontalPress", target: 100, start: start,
            deadline: start.adding(days: 120))
        let onPace = (0..<6).map { (start.adding(days: $0 * 7), 80 + Double($0) * 1.3) }
        #expect(Trajectories.assess(onPace, goal: goal, today: start.adding(days: 35)) == .onPace)
        let flat = (0..<6).map { (start.adding(days: $0 * 7), 80.0) }
        #expect(Trajectories.assess(flat, goal: goal, today: start.adding(days: 35)) == .stalled)
        let down = (0..<6).map { (start.adding(days: $0 * 7), 85 - Double($0) * 1.5) }
        #expect(Trajectories.assess(down, goal: goal, today: start.adding(days: 35)) == .regressing)
    }

    @Test func aGoalToGetSmallerReadsTheTrendTheOtherWay() {
        let start = Day(year: 2026, month: 1, day: 1)
        let waist = TargetGoal(stat: .vitality, title: "Waist 80", metric: "waist", target: 80, start: start, deadline: start.adding(days: 120))
        func weekly(_ value: (Int) -> Double) -> [(day: Day, value: Double)] { (0..<6).map { (start.adding(days: $0 * 7), value($0)) } }
        let today = start.adding(days: 35)
        #expect(Trajectories.assess(weekly { 88 - 0.47 * Double($0) }, goal: waist, today: today) == .onPace)
        #expect(Trajectories.assess(weekly { 88 - Double($0) }, goal: waist, today: today) == .ahead)
        #expect(Trajectories.assess(weekly { _ in 88 }, goal: waist, today: today) == .stalled)
        #expect(Trajectories.assess(weekly { 88 + 0.3 * Double($0) }, goal: waist, today: today) == .regressing)
        #expect(Trajectories.assess(Array(weekly { 88 - Double($0) }.prefix(2)), goal: waist, today: today) == .notEnoughData)
    }

    @Test func pastTheDeadlineAReachedGoalIsAheadAndAMissedOneStalled() {
        let start = Day(year: 2026, month: 1, day: 1)
        let goal = TargetGoal(
            stat: .strength, title: "Bench 100", metric: "category:horizontalPress", target: 100, start: start,
            deadline: start.adding(days: 35))
        let today = start.adding(days: 49)
        #expect(Trajectories.assess((0..<8).map { (start.adding(days: $0 * 7), 90 + 2 * Double($0)) }, goal: goal, today: today) == .ahead)
        #expect(Trajectories.assess((0..<8).map { (start.adding(days: $0 * 7), 80 + 0.5 * Double($0)) }, goal: goal, today: today) == .stalled)
    }

    @Test func heartRateRecoveryTrendsPerWeek() {
        let start = Day(year: 2026, month: 1, day: 1)
        let improving = (0..<4).map { (day: start.adding(days: $0 * 7), drop: 20 + 2 * Double($0)) }
        #expect(abs((HeartRateRecovery.trend(improving) ?? 0) - 2) < 1e-9)
        #expect(HeartRateRecovery.trend(Array(improving.prefix(3))) == nil)
        #expect(HeartRateRecovery.trend((0..<4).map { (day: start, drop: 20 + Double($0)) }) == nil)
    }
}
