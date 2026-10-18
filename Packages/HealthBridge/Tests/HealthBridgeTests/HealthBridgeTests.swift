import Foundation
import Synchronization
import SystemCore
import Testing
@testable import HealthBridge
#if canImport(HealthKit)
import HealthKit
#endif

private let chicago: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    chicago.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

#if canImport(HealthKit)
@Suite struct MappingTests {
    /// Activities recorded under a broader Health type, and the type they come back as.
    static let lossy: [ActivityType: (HKWorkoutActivityType, ActivityType)] = [
        .spin: (.cycling, .cycling),
        .hotYoga: (.yoga, .yoga),
        .judo: (.martialArts, .bjj),
        .mma: (.martialArts, .bjj),
    ]

    @Test(arguments: ActivityType.allCases)
    func roundTrips(_ activity: ActivityType) {
        let workoutType = HealthMapping.workoutType(for: activity)
        if let (expectedType, comesBackAs) = Self.lossy[activity] {
            #expect(workoutType == expectedType)
            #expect(HealthMapping.activityType(for: workoutType) == comesBackAs)
        } else {
            #expect(HealthMapping.activityType(for: workoutType) == activity)
        }
    }

    @Test func namedMappings() {
        #expect(HealthMapping.workoutType(for: .bjj) == .martialArts)
        #expect(HealthMapping.workoutType(for: .muayThai) == .kickboxing)
        #expect(HealthMapping.workoutType(for: .strength) == .traditionalStrengthTraining)
        #expect(HealthMapping.activityType(for: .functionalStrengthTraining) == .strength)
        #expect(HealthMapping.activityType(for: .basketball) == .teamSport)
        #expect(HealthMapping.activityType(for: .pickleball) == .racquet)
        #expect(HealthMapping.activityType(for: .golf) == .other)
    }
}

@Suite struct DietaryTests {
    func values(_ nutrients: Nutrients, micros: [String: Double] = [:]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: HealthTypes.dietaryValues(nutrients, micros: micros).map { ($0.1, $0.2) })
    }

    @Test func macrosWinAndMissingValuesDropOut() {
        let food = Nutrients(kcal: 210, protein: 12, carbs: 30, fat: 4, fiber: 5, sodium: 380)
        let written = values(food, micros: ["kcal": 1, "fiber": 99, "vitaminD": 2.5, "water": 240, "notANutrient": 7])
        #expect(written == ["kcal": 210, "protein": 12, "carbs": 30, "fat": 4, "fiber": 5, "sodium": 380, "vitaminD": 2.5, "water": 240])
        #expect(values(Nutrients(kcal: 0, protein: 0, carbs: 0, fat: 0)).keys.sorted() == ["carbs", "fat", "kcal", "protein"],
                "unknown sugar, saturated fat and sodium aren't written as zero")
    }

    @Test func unitsMatchTheCatalog() throws {
        let byKey = Dictionary(uniqueKeysWithValues: HealthTypes.dietary.map { ($0.key, $0) })
        #expect(byKey.count == HealthTypes.dietary.count, "one Health type per key")
        let milligrams = HKUnit.gramUnit(with: .milli), micrograms = HKUnit.gramUnit(with: .micro)
        for key in ["sodium", "potassium", "calcium", "iron", "magnesium", "zinc", "vitaminC", "caffeine", "cholesterol"] {
            #expect(byKey[key]?.unit == milligrams, "\(key)")
        }
        for key in ["selenium", "vitaminA", "vitaminD", "vitaminK", "folate", "vitaminB12"] {
            #expect(byKey[key]?.unit == micrograms, "\(key)")
        }
        let water = try #require(byKey["water"])
        #expect(water.type == HKQuantityType(.dietaryWater))
        #expect(water.unit == .literUnit(with: .milli))
        #expect(byKey["kcal"]?.type == HKQuantityType(.dietaryEnergyConsumed))
        #expect(byKey["satFat"]?.type == HKQuantityType(.dietaryFatSaturated))
        for type in HealthTypes.dietary {
            #expect(type.type.is(compatibleWith: type.unit), "\(type.key)")
        }
        #expect(HealthTypes.syncIdentifier(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, key: "kcal")
                == "00000000-0000-0000-0000-000000000001.kcal")
    }
}
#endif

@Suite struct SleepTests {
    @Test func nightBelongsToTheDayItEnds() {
        #expect(HealthMath.night(endingAt: date(2026, 10, 15, 6, 30), calendar: chicago) == Day(year: 2026, month: 10, day: 15))
        #expect(HealthMath.night(endingAt: date(2026, 10, 15, 11, 59), calendar: chicago) == Day(year: 2026, month: 10, day: 15))
        // Anything ending from noon on belongs to the next morning's night.
        #expect(HealthMath.night(endingAt: date(2026, 10, 15, 12, 0), calendar: chicago) == Day(year: 2026, month: 10, day: 16))
        #expect(HealthMath.night(endingAt: date(2026, 10, 15, 23, 45), calendar: chicago) == Day(year: 2026, month: 10, day: 16))
    }

    @Test func overlappingSourcesCountOnce() {
        let watch = [
            DateInterval(start: date(2026, 10, 14, 23), end: date(2026, 10, 15, 2)),
            DateInterval(start: date(2026, 10, 15, 2, 30), end: date(2026, 10, 15, 6)),
        ]
        let phone = [DateInterval(start: date(2026, 10, 15, 1), end: date(2026, 10, 15, 3))]
        let hours = HealthMath.sleepHours(watch + phone, calendar: chicago)
        // 23:00–03:00 merged, then 03:00–06:00 merged into it: 7 hours.
        #expect(hours == [Day(year: 2026, month: 10, day: 15): 7])
    }

    @Test func nightsAcrossDaylightSavingChanges() {
        // Chicago falls back at 2:00 on 1 November 2026 and springs forward at 2:00 on 8 March.
        let fallBack = [DateInterval(start: date(2026, 10, 31, 22), end: date(2026, 11, 1, 6))]
        #expect(HealthMath.sleepHours(fallBack, calendar: chicago) == [Day(year: 2026, month: 11, day: 1): 9], "the extra hour is slept")
        let springForward = [DateInterval(start: date(2026, 3, 7, 22), end: date(2026, 3, 8, 6))]
        #expect(HealthMath.sleepHours(springForward, calendar: chicago) == [Day(year: 2026, month: 3, day: 8): 7])
        #expect(HealthMath.night(endingAt: date(2026, 11, 1, 11, 59), calendar: chicago) == Day(year: 2026, month: 11, day: 1))
        #expect(HealthMath.night(endingAt: date(2026, 11, 1, 12), calendar: chicago) == Day(year: 2026, month: 11, day: 2))
        #expect(HealthMath.night(endingAt: date(2026, 3, 8, 12), calendar: chicago) == Day(year: 2026, month: 3, day: 9))
    }

    @Test func nightsSplitAtNoon() {
        let intervals = [
            DateInterval(start: date(2026, 10, 14, 0), end: date(2026, 10, 14, 7)),
            DateInterval(start: date(2026, 10, 14, 14), end: date(2026, 10, 14, 14, 30)),
            DateInterval(start: date(2026, 10, 14, 22), end: date(2026, 10, 15, 6)),
        ]
        let hours = HealthMath.sleepHours(intervals, calendar: chicago)
        #expect(hours[Day(year: 2026, month: 10, day: 14)] == 7)
        #expect(hours[Day(year: 2026, month: 10, day: 15)] == 8.5)
    }

    @Test func recoveryDaysCoverEveryDay() {
        let start = Day(year: 2026, month: 10, day: 10)
        let end = Day(year: 2026, month: 10, day: 13)
        let days = HealthMath.recoveryDays(from: start, through: end, sleep: [start: 7.5],
                                           hrv: [end: 62], restingHeartRate: [:])
        #expect(days.map(\.day) == [start, start.adding(days: 1), start.adding(days: 2), end])
        #expect(days.first?.sleepHours == 7.5)
        #expect(days.last?.hrv == 62)
        #expect(days[1] == RecoveryDay(day: start.adding(days: 1)))
        #expect(HealthMath.recoveryDays(from: start, through: end, sleep: [:], hrv: [:], restingHeartRate: [:]).isEmpty)
        // Data only outside the range (a nap that counts towards tomorrow's night) still means nothing to report.
        #expect(HealthMath.recoveryDays(from: start, through: end, sleep: [end.adding(days: 1): 0.5], hrv: [:],
                                        restingHeartRate: [:]).isEmpty)
        #expect(HealthMath.recoveryDays(from: end, through: start, sleep: [start: 7], hrv: [:], restingHeartRate: [:]).isEmpty)
    }
}

@Suite struct IntensityTests {
    @Test func maxHeartRateFallsWithAge() {
        #expect(HealthMath.maxHeartRate(age: 20) == 194)
        #expect(HealthMath.maxHeartRate(age: 40) == 180)
    }

    @Test func intensityTracksShareOfMax() {
        #expect(HealthMath.intensity(averageHeartRate: 90, maxHeartRate: 180) == 2)
        #expect(HealthMath.intensity(averageHeartRate: 126, maxHeartRate: 180) == 6)
        #expect(HealthMath.intensity(averageHeartRate: 144, maxHeartRate: 180) == 8)
        #expect(HealthMath.intensity(averageHeartRate: 175, maxHeartRate: 180) == 10)
        #expect(HealthMath.intensity(averageHeartRate: 50, maxHeartRate: 180) == 1)
        #expect(HealthMath.intensity(averageHeartRate: 0, maxHeartRate: 180) == nil)
    }

    @Test func ageFromBirthDate() {
        let birth = DateComponents(year: 1990, month: 10, day: 20)
        #expect(HealthMath.age(birth: birth, on: date(2026, 10, 15, 12), calendar: chicago) == 35)
        #expect(HealthMath.age(birth: birth, on: date(2026, 10, 20, 12), calendar: chicago) == 36)
        #expect(HealthMath.age(birth: DateComponents(month: 1, day: 1), on: date(2026, 10, 15, 12), calendar: chicago) == nil)
        #expect(HealthMath.age(birth: DateComponents(year: 2030, month: 1, day: 1), on: date(2026, 10, 15, 12), calendar: chicago) == nil)
    }

    @Test(arguments: [Calendar.Identifier.buddhist, .japanese, .republicOfChina, .persian, .hebrew, .islamicUmmAlQura])
    func ageIsTheSameInEveryCalendar(_ identifier: Calendar.Identifier) {
        // HealthKit's birth date is Gregorian whatever calendar the person uses.
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = chicago.timeZone
        let birth = DateComponents(year: 1990, month: 10, day: 20)
        #expect(HealthMath.age(birth: birth, on: date(2026, 10, 15, 12), calendar: calendar) == 35)
        #expect(HealthMath.age(birth: birth, on: date(2026, 10, 20, 12), calendar: calendar) == 36)
    }

    @Test func mergedDurationHandlesGapsAndContainment() {
        let base = date(2026, 1, 1, 0)
        let intervals = [
            DateInterval(start: base, duration: 3600),
            DateInterval(start: base.addingTimeInterval(600), duration: 600),
            DateInterval(start: base.addingTimeInterval(7200), duration: 1800),
        ]
        #expect(HealthMath.mergedDuration(intervals) == 5400)
        #expect(HealthMath.mergedDuration([]) == 0)
    }
}

@Suite struct UnavailableTests {
    #if os(macOS)
    @Test func unavailableOnMac() {
        #expect(!HealthBridge.shared.isAvailable)
    }
    #endif

    /// Where this device has Health (an iPhone simulator), the shared bridge is the real thing.
    @Test(.enabled(if: !HealthBridge.shared.isAvailable, "Health data is available here"))
    func everythingIsEmptyWhenUnavailable() async throws {
        try await expectEverythingEmpty(HealthBridge.shared)
    }

    @Test func aDisabledBridgeIsUnavailableEverywhere() async throws {
        let bridge = HealthBridge()
        bridge.disable()
        #expect(!bridge.isAvailable)
        try await expectEverythingEmpty(bridge)
    }

    func expectEverythingEmpty(_ bridge: HealthBridge) async throws {
        let past = Date().addingTimeInterval(-30 * 86400)
        #expect(await bridge.requestAuthorization() == false)
        #expect(await bridge.latestBodyweight() == nil)
        #expect(await bridge.bodyweights(since: past).isEmpty)
        #expect(await bridge.latestHeight() == nil)
        #expect(await bridge.latestVO2Max() == nil)
        #expect(await bridge.latestRestingHeartRate() == nil)
        #expect(await bridge.recoveryDays(since: Day.today.adding(days: -14)).isEmpty)
        #expect(await bridge.externalWorkouts(since: past, excludingBundlePrefixes: ["com.example.lifttrack"]).isEmpty)
        #expect(await bridge.heartRateSamples(from: past, to: Date()).isEmpty)
        try await bridge.saveStrengthWorkout(id: UUID(), version: 1, start: past, end: past.addingTimeInterval(3600),
                                             title: "Push", energyKcal: 250)
        await bridge.deleteWorkout(id: UUID())
        await bridge.saveMeasurements(BodyMeasurements(day: .today, bodyFatPercent: 15, waistCm: 82))
        await bridge.deleteMeasurements(id: UUID())
        await bridge.saveFoods([HealthFood(id: UUID(), date: past, name: "Oats", nutrients: Nutrients(kcal: 150, protein: 5, carbs: 27, fat: 3),
                                           version: 1)])
        await bridge.deleteFoods(ids: [UUID()])
        #expect(await bridge.weighIns(since: past, ownBundlePrefixes: []).isEmpty)
        #expect(bridge.observeChanges {} == nil)
    }
}

@Suite struct WriteQueueTests {
    @Test func jobsForAnIDRunInTheOrderAsked() async {
        let queue = WriteQueue()
        let log = Mutex<[String]>([])
        let (gate, open) = AsyncStream.makeStream(of: Void.self)
        let food = UUID(), water = UUID()

        async let save: Void = queue.run([food]) {
            log.withLock { $0.append("save started") }
            for await _ in gate { break }
            log.withLock { $0.append("save finished") }
        }
        while log.withLock({ $0.isEmpty }) { await Task.yield() }
        // Another food's job doesn't wait.
        await queue.run([water]) { log.withLock { $0.append("water") } }
        // An undo of the food waits for its save, however long Health takes.
        async let undo: Void = queue.run([water, food]) { log.withLock { $0.append("undo") } }
        for _ in 0..<200 { await Task.yield() }
        #expect(log.withLock { $0 } == ["save started", "water"])

        open.yield()
        open.finish()
        _ = await (save, undo)
        #expect(log.withLock { $0 } == ["save started", "water", "save finished", "undo"])
        #expect(queue.isIdle)
    }
}
