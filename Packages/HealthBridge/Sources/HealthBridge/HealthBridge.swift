import Foundation
import OSLog
import SystemCore
#if canImport(HealthKit)
import HealthKit
import Synchronization
#endif

let healthLog = Logger(subsystem: "dev.svindland.stadig", category: "health")

/// Thread-safe facade over HKHealthStore. All methods are safe to call when Health is unavailable or
/// not authorised: they return nil/empty.
public final class HealthBridge: @unchecked Sendable {
    public static let shared = HealthBridge()

    #if canImport(HealthKit)
    private let lazyStore = Mutex<HKHealthStore?>(nil)
    private let switchedOff = Mutex(false)
    /// Food writes to Health, in order per food (see `WriteQueue`).
    let foodWrites = WriteQueue()
    /// Body measurement writes, in order per measurement, so a delete waits for a save on its way.
    let measurementWrites = WriteQueue()
    #endif

    init() {}
}

#if canImport(HealthKit)
extension HealthBridge {
    /// Whether this device keeps Health data and the bridge may use it. Always false on the Mac,
    /// and after `disable()`.
    public var isAvailable: Bool {
        guard !switchedOff.withLock({ $0 }) else { return false }
        #if os(macOS)
        return false
        #else
        return HKHealthStore.isHealthDataAvailable()
        #endif
    }

    /// Switches Health off for the rest of the process: from then on the bridge behaves as if the
    /// device kept no Health data (no permission prompts, empty reads, writes skipped, no live
    /// workouts). UI tests and unit-test hosts call it before anything touches Health.
    public func disable() {
        switchedOff.withLock { $0 = true }
    }

    /// The one store, created on first use; nil when Health is unavailable.
    var store: HKHealthStore? {
        guard isAvailable else { return nil }
        return lazyStore.withLock { store in
            if let store { return store }
            let created = HKHealthStore()
            store = created
            return created
        }
    }

    // MARK: Authorization

    /// Training reads body mass, height, body fat %, waist circumference, resting HR, HRV SDNN, VO2
    /// max, sleep analysis, heart rate, steps, workouts, active energy and date of birth (for an age-based
    /// max heart rate), and writes workouts, waist circumference, body fat %, active energy (and
    /// heart rate on the Watch, for live sessions). Nutrition reads body mass, height, body
    /// composition, workouts and date of birth, and writes food and body mass. Returns whether
    /// the request completed.
    public func requestAuthorization(_ access: HealthAccess = .training) async -> Bool {
        guard let store else { return false }
        do {
            try await store.requestAuthorization(toShare: HealthTypes.shareTypes(access), read: HealthTypes.readTypes(access))
            return true
        } catch {
            return false
        }
    }

    /// Asks again only when types were added since the person last answered, and only if they
    /// answered before (sharing workouts was decided): never a first prompt out of nowhere.
    public func requestAddedTypes(_ access: HealthAccess = .training) async {
        guard let store, store.authorizationStatus(for: HKObjectType.workoutType()) != .notDetermined else { return }
        let share = HealthTypes.shareTypes(access), read = HealthTypes.readTypes(access)
        guard (try? await store.statusForAuthorizationRequest(toShare: share, read: read)) == .shouldRequest else { return }
        _ = try? await store.requestAuthorization(toShare: share, read: read)
    }

    // MARK: Body

    /// The most recent body mass sample.
    public func latestBodyweight() async -> (kg: Double, date: Date)? {
        guard let latest = await latest(HealthTypes.bodyMass, unit: HealthTypes.kg) else { return nil }
        return (latest.value, latest.date)
    }

    /// Body mass samples since `since`, oldest first.
    public func bodyweights(since: Date) async -> [(date: Date, kg: Double)] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
        return await quantitySamples(HealthTypes.bodyMass, predicate: predicate, newestFirst: false)
            .map { ($0.endDate, $0.quantity.doubleValue(for: HealthTypes.kg)) }
    }

    /// The most recent body-fat sample (a smart scale or a scan), as a percentage.
    public func latestBodyFat() async -> (percent: Double, date: Date)? {
        guard let latest = await latest(HealthTypes.bodyFat, unit: .percent()) else { return nil }
        return (latest.value * 100, latest.date)
    }

    /// Latest height in cm.
    public func latestHeight() async -> Double? { await latest(HealthTypes.height, unit: HealthTypes.cm)?.value }

    /// Latest VO2 max in ml/kg/min.
    public func latestVO2Max() async -> Double? { await latest(HealthTypes.vo2Max, unit: HealthTypes.vo2)?.value }

    /// Latest resting heart rate in bpm.
    public func latestRestingHeartRate() async -> Double? { await latest(HealthTypes.restingHeartRate, unit: HealthTypes.bpm)?.value }

    // MARK: Recovery

    /// One RecoveryDay per calendar day since `since`: sleep hours for the night ending that morning
    /// (asleep stages only), mean HRV SDNN (ms), resting HR. Empty when Health has nothing for the window.
    public func recoveryDays(since: Day) async -> [RecoveryDay] {
        guard let store else { return [] }
        let calendar = Calendar.current
        let today = Day(Date(), calendar: calendar)
        guard since <= today else { return [] }
        let start = since.date(calendar: calendar)
        async let sleep = sleepHours(store: store, nightsFrom: since, calendar: calendar)
        async let hrv = dailyAverages(store: store, type: HealthTypes.hrv, unit: HealthTypes.ms, from: start, calendar: calendar)
        async let resting = dailyAverages(store: store, type: HealthTypes.restingHeartRate, unit: HealthTypes.bpm, from: start,
                                          calendar: calendar)
        return await HealthMath.recoveryDays(from: since, through: today, sleep: sleep, hrv: hrv, restingHeartRate: resting)
    }

    // MARK: Steps

    /// Steps per calendar day from `since` through today (today so far), every source merged the
    /// way Health shows them, so an iPhone and a Watch don't double count. Oldest first.
    public func dailySteps(since: Day) async -> [StepDay] {
        guard let store else { return [] }
        let calendar = Calendar.current
        let start = since.date(calendar: calendar)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HealthTypes.steps,
                                       predicate: HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)),
            options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
        guard let collection = try? await descriptor.result(for: store) else { return [] }
        return collection.statistics().compactMap { statistics in
            guard let sum = statistics.sumQuantity()?.doubleValue(for: .count()) else { return nil }
            return StepDay(day: Day(statistics.startDate, calendar: calendar), steps: Int(sum.rounded()))
        }
    }

    // MARK: Workouts and heart rate

    /// Workouts written by other apps since `since`, oldest first. Sources whose bundle identifier
    /// starts with one of `excludingBundlePrefixes` (this app and its Watch app, under any id it has
    /// had) are skipped. Intensity comes
    /// from average heart rate against an age-based max when both are known, else the activity's
    /// typical intensity.
    public func externalWorkouts(since: Date, excludingBundlePrefixes: [String]) async -> [ActivityLog] {
        guard let store else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let workouts = try? await descriptor.result(for: store) else { return [] }
        let birth = try? store.dateOfBirthComponents()

        var logs: [ActivityLog] = []
        for workout in workouts {
            let source = workout.sourceRevision.source
            if source.bundleIdentifier.hasAnyPrefix(excludingBundlePrefixes) { continue }
            var heartRate = workout.statistics(for: HealthTypes.heartRate)?.averageQuantity()?.doubleValue(for: HealthTypes.bpm)
            if heartRate == nil {
                heartRate = await averageHeartRate(store: store, from: workout.startDate, to: workout.endDate)
            }
            var intensity: Int?
            if let heartRate, let birth, let age = HealthMath.age(birth: birth, on: workout.startDate) {
                intensity = HealthMath.intensity(averageHeartRate: heartRate, maxHeartRate: HealthMath.maxHeartRate(age: age))
            }
            logs.append(ActivityLog(
                id: workout.uuid, type: HealthMapping.activityType(for: workout.workoutActivityType),
                start: workout.startDate, minutes: Int((workout.duration / 60).rounded()), intensity: intensity,
                source: .health(workout.uuid, sourceName: source.name), averageHeartRate: heartRate,
                distanceMeters: distance(of: workout)))
        }
        return logs
    }

    /// Heart rate samples in the window, oldest first.
    public func heartRateSamples(from: Date, to: Date) async -> [(date: Date, bpm: Double)] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        return await quantitySamples(HealthTypes.heartRate, predicate: predicate, newestFirst: false, sortByStart: true)
            .map { ($0.startDate, $0.quantity.doubleValue(for: HealthTypes.bpm)) }
    }

    // MARK: Writes

    /// Saves (or replaces) a traditional-strength-training workout keyed by a sync id in metadata
    /// (HKMetadataKeySyncIdentifier = id.uuidString, HKMetadataKeySyncVersion = version), so a higher
    /// version replaces the earlier copy. Energy is written when given and sharing it is authorised.
    /// Does nothing when Health is unavailable; throws when HealthKit refuses the save.
    public func saveStrengthWorkout(id: UUID, version: Int, start: Date, end: Date, title: String,
                                    energyKcal: Double?) async throws {
        guard let store else { return }
        let end = max(start, end)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        let energyID = Self.energySyncIdentifier(id)
        do {
            try await builder.beginCollection(at: start)
            if store.authorizationStatus(for: HealthTypes.activeEnergy) == .sharingAuthorized {
                if let energyKcal, energyKcal > 0 {
                    let energy = HKQuantitySample(
                        type: HealthTypes.activeEnergy, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal),
                        start: start, end: end,
                        metadata: [HKMetadataKeySyncIdentifier: energyID, HKMetadataKeySyncVersion: version])
                    try await builder.addSamples([energy])
                } else {
                    _ = try? await store.deleteObjects(of: HealthTypes.activeEnergy, predicate: Self.syncPredicate(energyID))
                }
            }
            try await builder.addMetadata([
                HKMetadataKeySyncIdentifier: id.uuidString,
                HKMetadataKeySyncVersion: version,
                HKMetadataKeyIndoorWorkout: true,
                Self.titleMetadataKey: title,
            ])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            builder.discardWorkout()
            throw error
        }
    }

    /// Deletes the workout saved under this sync id, with its energy sample.
    public func deleteWorkout(id: UUID) async {
        guard let store else { return }
        _ = try? await store.deleteObjects(of: HKObjectType.workoutType(), predicate: Self.syncPredicate(id.uuidString))
        _ = try? await store.deleteObjects(of: HealthTypes.activeEnergy, predicate: Self.syncPredicate(Self.energySyncIdentifier(id)))
    }

    /// Writes waist circumference and body fat % if present in the measurements. Keyed by the
    /// measurement's id, so saving an edited entry replaces the earlier samples, and a field cleared
    /// in the edit removes its sample.
    public func saveMeasurements(_ measurements: BodyMeasurements) async {
        guard let store else { return }
        let calendar = Calendar.current
        let midnight = measurements.day.date(calendar: calendar)
        let date = measurements.day == Day(Date(), calendar: calendar)
            ? Date()
            : calendar.date(bySettingHour: 12, minute: 0, second: 0, of: midnight) ?? midnight
        let version = Int(Date().timeIntervalSince1970 * 1000)

        func sample(_ type: HKQuantityType, _ quantity: HKQuantity, key: String) -> HKQuantitySample {
            HKQuantitySample(type: type, quantity: quantity, start: date, end: date, metadata: [
                HKMetadataKeySyncIdentifier: Self.measurementSyncIdentifier(measurements.id, key),
                HKMetadataKeySyncVersion: version,
            ])
        }
        var samples: [HKQuantitySample] = []
        var cleared: [(type: HKQuantityType, key: String)] = []
        if let waist = measurements.waistCm, waist > 0 {
            samples.append(sample(HealthTypes.waist, HKQuantity(unit: HealthTypes.cm, doubleValue: waist), key: Self.waistKey))
        } else {
            cleared.append((HealthTypes.waist, Self.waistKey))
        }
        if let bodyFat = measurements.bodyFatPercent, bodyFat > 0 {
            samples.append(sample(HealthTypes.bodyFat, HKQuantity(unit: .percent(), doubleValue: bodyFat / 100), key: Self.bodyFatKey))
        } else {
            cleared.append((HealthTypes.bodyFat, Self.bodyFatKey))
        }
        cleared.removeAll { store.authorizationStatus(for: $0.type) != .sharingAuthorized }
        samples.removeAll { store.authorizationStatus(for: $0.quantityType) != .sharingAuthorized }
        guard !cleared.isEmpty || !samples.isEmpty else { return }
        let id = measurements.id
        await measurementWrites.run([id]) { [samples, cleared] in
            // A reading deleted here would otherwise come back as Health's latest body fat.
            for field in cleared {
                _ = try? await store.deleteObjects(of: field.type, predicate: Self.syncPredicate(Self.measurementSyncIdentifier(id, field.key)))
            }
            guard !samples.isEmpty else { return }
            try? await store.save(samples)
        }
    }

    /// Deletes the waist and body-fat samples saved for this measurement, after any save of it still
    /// on its way.
    public func deleteMeasurements(id: UUID) async {
        guard let store else { return }
        await measurementWrites.run([id]) {
            for (type, key) in [(HealthTypes.waist, Self.waistKey), (HealthTypes.bodyFat, Self.bodyFatKey)] {
                _ = try? await store.deleteObjects(of: type, predicate: Self.syncPredicate(Self.measurementSyncIdentifier(id, key)))
            }
        }
    }

    // MARK: Observation

    /// Delivers a callback whenever new workouts or body mass samples arrive (HKObserverQuery); returns
    /// a token to stop it. Observation stops when the token is released.
    public func observeChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject? {
        guard let store else { return nil }
        let query = HKObserverQuery(queryDescriptors: [
            HKQueryDescriptor(sampleType: HKObjectType.workoutType(), predicate: nil),
            HKQueryDescriptor(sampleType: HealthTypes.bodyMass, predicate: nil),
        ]) { _, _, completion, error in
            if error == nil { handler() }
            completion()
        }
        store.execute(query)
        return ObserverToken(store: store, query: query)
    }
}

// MARK: - Internals

extension HealthBridge {
    /// Custom metadata key holding a saved workout's title.
    static let titleMetadataKey = "HealthBridgeTitle"

    static func energySyncIdentifier(_ id: UUID) -> String { "\(id.uuidString).energy" }

    static let waistKey = "waist"
    static let bodyFatKey = "bodyFat"

    static func measurementSyncIdentifier(_ id: UUID, _ key: String) -> String { "\(id.uuidString).\(key)" }

    static func syncPredicate(_ identifier: String) -> NSPredicate {
        HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [identifier])
    }

    private func quantitySamples(_ type: HKQuantityType, predicate: NSPredicate?, newestFirst: Bool,
                                 sortByStart: Bool = false, limit: Int? = nil) async -> [HKQuantitySample] {
        guard let store else { return [] }
        let order: SortOrder = newestFirst ? .reverse : .forward
        let sort = sortByStart ? SortDescriptor(\HKQuantitySample.startDate, order: order)
                               : SortDescriptor(\HKQuantitySample.endDate, order: order)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)], sortDescriptors: [sort], limit: limit)
        return (try? await descriptor.result(for: store)) ?? []
    }

    private func latest(_ type: HKQuantityType, unit: HKUnit) async -> (value: Double, date: Date)? {
        guard let sample = await quantitySamples(type, predicate: nil, newestFirst: true, limit: 1).first else { return nil }
        return (sample.quantity.doubleValue(for: unit), sample.endDate)
    }

    private func averageHeartRate(store: HKHealthStore, from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HealthTypes.heartRate, predicate: predicate), options: .discreteAverage)
        return try? await descriptor.result(for: store)?.averageQuantity()?.doubleValue(for: HealthTypes.bpm)
    }

    /// Total distance recorded with the workout, across whichever distance types it carries.
    private func distance(of workout: HKWorkout) -> Double? {
        let meters = workout.allStatistics
            .filter { $0.key.is(compatibleWith: .meter()) }
            .compactMap { $0.value.sumQuantity()?.doubleValue(for: .meter()) }
        return meters.isEmpty ? nil : meters.reduce(0, +)
    }

    /// Hours asleep per night from `first` on, counting only the asleep stages.
    private func sleepHours(store: HKHealthStore, nightsFrom first: Day, calendar: Calendar) async -> [Day: Double] {
        let previousMidnight = first.adding(days: -1).date(calendar: calendar)
        let windowStart = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: previousMidnight) ?? previousMidnight
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HealthTypes.sleep,
                                         predicate: HKQuery.predicateForSamples(withStart: windowStart, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await descriptor.result(for: store) else { return [:] }
        let intervals = samples
            .filter { HealthTypes.asleepValues.contains($0.value) }
            .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
        return HealthMath.sleepHours(intervals, calendar: calendar).filter { $0.key >= first }
    }

    /// Mean of a discrete quantity per calendar day from `start` on.
    private func dailyAverages(store: HKHealthStore, type: HKQuantityType, unit: HKUnit, from start: Date,
                               calendar: Calendar) async -> [Day: Double] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type,
                                       predicate: HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)),
            options: .discreteAverage, anchorDate: start, intervalComponents: DateComponents(day: 1))
        guard let collection = try? await descriptor.result(for: store) else { return [:] }
        var averages: [Day: Double] = [:]
        for statistics in collection.statistics() {
            if let value = statistics.averageQuantity()?.doubleValue(for: unit) {
                averages[Day(statistics.startDate, calendar: calendar)] = value
            }
        }
        return averages
    }
}

/// Stops an observer query when released.
private final class ObserverToken: Sendable {
    let store: HKHealthStore
    let query: HKObserverQuery

    init(store: HKHealthStore, query: HKObserverQuery) {
        self.store = store
        self.query = query
    }

    deinit { store.stop(query) }
}

/// The HealthKit types and units the bridge reads and writes.
enum HealthTypes {
    static let bodyMass = HKQuantityType(.bodyMass)
    static let height = HKQuantityType(.height)
    static let bodyFat = HKQuantityType(.bodyFatPercentage)
    static let waist = HKQuantityType(.waistCircumference)
    static let restingHeartRate = HKQuantityType(.restingHeartRate)
    static let hrv = HKQuantityType(.heartRateVariabilitySDNN)
    static let vo2Max = HKQuantityType(.vo2Max)
    static let heartRate = HKQuantityType(.heartRate)
    static let activeEnergy = HKQuantityType(.activeEnergyBurned)
    static let steps = HKQuantityType(.stepCount)
    static let sleep = HKCategoryType(.sleepAnalysis)

    static let kg = HKUnit.gramUnit(with: .kilo)
    static let cm = HKUnit.meterUnit(with: .centi)
    static let ms = HKUnit.secondUnit(with: .milli)
    static let bpm = HKUnit.count().unitDivided(by: .minute())
    static let vo2 = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

    static let asleepValues: Set<Int> = Set([
        HKCategoryValueSleepAnalysis.asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM,
    ].map(\.rawValue))

    static func readTypes(_ access: HealthAccess) -> Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if access.contains(.training) {
            types.formUnion([bodyMass, height, bodyFat, waist, restingHeartRate, hrv, vo2Max, sleep, heartRate, activeEnergy, steps,
                             HKObjectType.workoutType(), HKCharacteristicType(.dateOfBirth)])
        }
        if access.contains(.nutrition) {
            types.formUnion([bodyMass, height, bodyFat, waist, HKObjectType.workoutType(), HKCharacteristicType(.dateOfBirth)])
        }
        return types
    }

    static func shareTypes(_ access: HealthAccess) -> Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        if access.contains(.training) {
            types.formUnion([HKObjectType.workoutType(), waist, bodyFat, activeEnergy])
            #if os(watchOS)
            types.insert(heartRate)
            #endif
        }
        if access.contains(.nutrition) {
            types.insert(bodyMass)
            types.formUnion(dietary.map(\.type))
        }
        return types
    }
}

#else

extension HealthBridge {
    public var isAvailable: Bool { false }
    public func disable() {}
    public func requestAuthorization(_ access: HealthAccess = .training) async -> Bool { false }
    public func requestAddedTypes(_ access: HealthAccess = .training) async {}
    public func dailySteps(since: Day) async -> [StepDay] { [] }
    public func latestBodyweight() async -> (kg: Double, date: Date)? { nil }
    public func bodyweights(since: Date) async -> [(date: Date, kg: Double)] { [] }
    public func latestBodyFat() async -> (percent: Double, date: Date)? { nil }
    public func latestHeight() async -> Double? { nil }
    public func latestVO2Max() async -> Double? { nil }
    public func latestRestingHeartRate() async -> Double? { nil }
    public func recoveryDays(since: Day) async -> [RecoveryDay] { [] }
    public func externalWorkouts(since: Date, excludingBundlePrefixes: [String]) async -> [ActivityLog] { [] }
    public func heartRateSamples(from: Date, to: Date) async -> [(date: Date, bpm: Double)] { [] }
    public func saveStrengthWorkout(id: UUID, version: Int, start: Date, end: Date, title: String,
                                    energyKcal: Double?) async throws {}
    public func deleteWorkout(id: UUID) async {}
    public func saveMeasurements(_ measurements: BodyMeasurements) async {}
    public func deleteMeasurements(id: UUID) async {}
    public func observeChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject? { nil }
    public func weighIns(since: Date, ownBundlePrefixes: [String]) async -> [HealthWeight] { [] }
    public func weighInChanges(after anchor: Data?, since: Date, ownBundlePrefixes: [String]) async -> HealthWeightChanges? { nil }
    public func saveWeight(id: UUID, date: Date, kg: Double, version: Int) async {}
    public func deleteWeight(id: UUID) async {}
    public func saveFoods(_ foods: [HealthFood]) async {}
    public func deleteFoods(ids: [UUID]) async {}
}

#endif

extension String {
    /// Whether this starts with any of `prefixes`; empty prefixes match nothing.
    func hasAnyPrefix(_ prefixes: [String]) -> Bool {
        prefixes.contains { !$0.isEmpty && hasPrefix($0) }
    }
}
