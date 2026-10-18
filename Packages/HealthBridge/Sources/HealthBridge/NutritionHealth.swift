import Foundation
import SystemCore

#if canImport(HealthKit)
import HealthKit
#endif

/// Which app's permissions to ask for, so each asks only for what it uses.
public struct HealthAccess: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Lift Track: workouts, recovery, body composition.
    public static let training = HealthAccess(rawValue: 1)
    /// Macro Track: body mass and food.
    public static let nutrition = HealthAccess(rawValue: 2)
}

/// A body mass sample from Health.
public struct HealthWeight: Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var kg: Double
    public var sourceName: String

    public init(id: UUID, date: Date, kg: Double, sourceName: String) {
        self.id = id
        self.date = date
        self.kg = kg
        self.sourceName = sourceName
    }
}

/// What changed among Health's body mass samples since an anchor (`HealthBridge.weighInChanges`).
public struct HealthWeightChanges: Hashable, Sendable {
    /// Samples added since the anchor, from the date asked for on, leaving out this app's own;
    /// oldest first.
    public var added: [HealthWeight]
    /// Samples Health says were deleted since the anchor, whoever wrote them (Health keeps no source
    /// for a deletion). Only ever what Health reported: a read that fails gives no changes at all,
    /// and one that finds nothing deletes nothing. Match them to weigh-ins read from Health by sample
    /// id; a weigh-in this app wrote has an id of its own, never its sample's.
    public var deletedIDs: Set<UUID>
    /// Where the next read picks up. It counts in this device's Health database, so keep it on the
    /// device (not in a synced record) and pass it back next time.
    public var anchor: Data

    public init(added: [HealthWeight], deletedIDs: Set<UUID>, anchor: Data) {
        self.added = added
        self.deletedIDs = deletedIDs
        self.anchor = anchor
    }

    /// An added sample as the query found it, before the filters.
    struct Reading {
        var weight: HealthWeight
        var start: Date
        var bundleIdentifier: String
    }

    /// Additions kept to `since` on (by start, as `weighIns` reads them) and to other sources, less
    /// any also reported deleted, oldest first.
    init(readings: [Reading], deleted: [UUID], since: Date, ownBundlePrefixes: [String], anchor: Data) {
        let deletedIDs = Set(deleted)
        self.init(
            added:
                readings
                .filter { $0.start >= since && !$0.bundleIdentifier.hasAnyPrefix(ownBundlePrefixes) && !deletedIDs.contains($0.weight.id) }
                .map(\.weight)
                .sorted { $0.date < $1.date },
            deletedIDs: deletedIDs, anchor: anchor)
    }
}

/// One logged food as Health stores it: a food correlation of dietary samples.
public struct HealthFood: Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var name: String
    public var nutrients: Nutrients
    /// Vitamins, minerals and fat parts by catalog key, in the catalog's units (mg, µg or g), and
    /// "water" in millilitres.
    public var micros: [String: Double]
    /// Higher versions replace earlier copies.
    public var version: Int

    public init(id: UUID, date: Date, name: String, nutrients: Nutrients, micros: [String: Double] = [:], version: Int) {
        self.id = id
        self.date = date
        self.name = name
        self.nutrients = nutrients
        self.micros = micros
        self.version = version
    }
}

#if canImport(HealthKit)
extension HealthBridge {
    // MARK: Weight

    /// Body mass samples since `since`, oldest first, leaving out the ones this app wrote under any
    /// of `ownBundlePrefixes` (they're already its own manual weigh-ins).
    public func weighIns(since: Date, ownBundlePrefixes: [String]) async -> [HealthWeight] {
        guard let store else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [
                .quantitySample(
                    type: HealthTypes.bodyMass,
                    predicate: HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate))
            ],
            sortDescriptors: [SortDescriptor(\.endDate)])
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.compactMap { sample in
            let source = sample.sourceRevision.source
            if source.bundleIdentifier.hasAnyPrefix(ownBundlePrefixes) { return nil }
            return HealthWeight(
                id: sample.uuid, date: sample.endDate, kg: sample.quantity.doubleValue(for: HealthTypes.kg),
                sourceName: source.name)
        }
    }

    /// Body mass samples added and deleted since `anchor`, and the anchor to pass next time. The
    /// first read (a nil anchor, or one that can't be read) finds every sample and no deletions.
    /// Additions keep to `since` on and leave out this app's own, as in `weighIns`. Nil when Health
    /// is unavailable or the read fails: keep the old anchor and change nothing.
    ///
    /// The anchor moves past everything it has seen, so a sample left out (before `since`, or hidden
    /// because reading wasn't allowed, which Health doesn't tell apart from no data) never comes back
    /// as added; `weighIns` re-reads the whole window when that matters.
    public func weighInChanges(after anchor: Data?, since: Date, ownBundlePrefixes: [String]) async -> HealthWeightChanges? {
        guard let store else { return nil }
        // No date predicate: Health applies the predicate to deletions too, and a deleted sample has
        // no date left to match, so its deletion would never be reported.
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: HealthTypes.bodyMass)],
            anchor: anchor.flatMap(Self.queryAnchor))
        let result: HKAnchoredObjectQueryDescriptor<HKQuantitySample>.Result
        do {
            result = try await descriptor.result(for: store)
        } catch {
            healthLog.error("Couldn't read body mass changes: \(String(describing: error), privacy: .public)")
            return nil
        }
        guard let next = Self.anchorData(result.newAnchor) else { return nil }
        let readings = result.addedSamples.map { sample in
            let source = sample.sourceRevision.source
            return HealthWeightChanges.Reading(
                weight: HealthWeight(
                    id: sample.uuid, date: sample.endDate, kg: sample.quantity.doubleValue(for: HealthTypes.kg),
                    sourceName: source.name),
                start: sample.startDate, bundleIdentifier: source.bundleIdentifier)
        }
        return HealthWeightChanges(
            readings: readings, deleted: result.deletedObjects.map(\.uuid), since: since,
            ownBundlePrefixes: ownBundlePrefixes, anchor: next)
    }

    /// An anchor as `weighInChanges` hands it out.
    static func anchorData(_ anchor: HKQueryAnchor) -> Data? {
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        } catch {
            healthLog.error("Couldn't keep a Health anchor: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The anchor in `data`; nil, so the read starts over, when it isn't one.
    static func queryAnchor(_ data: Data) -> HKQueryAnchor? {
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        } catch {
            healthLog.error("Couldn't read a Health anchor, so reading from the start: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Saves (or replaces) a manual weigh-in, keyed by its id.
    public func saveWeight(id: UUID, date: Date, kg: Double, version: Int) async {
        guard let store, store.authorizationStatus(for: HealthTypes.bodyMass) == .sharingAuthorized else { return }
        let sample = HKQuantitySample(
            type: HealthTypes.bodyMass, quantity: HKQuantity(unit: HealthTypes.kg, doubleValue: kg),
            start: date, end: date,
            metadata: [HKMetadataKeySyncIdentifier: id.uuidString, HKMetadataKeySyncVersion: version])
        try? await store.save(sample)
    }

    public func deleteWeight(id: UUID) async {
        guard let store else { return }
        _ = try? await store.deleteObjects(of: HealthTypes.bodyMass, predicate: Self.syncPredicate(id.uuidString))
    }

    // MARK: Food

    /// Saves (or replaces) foods as food correlations. Earlier copies are removed first, so a
    /// nutrient cleared in an edit doesn't linger. One write for the batch. Runs after any earlier
    /// save or delete of the same foods has finished, so an undo right after logging still wins.
    public func saveFoods(_ foods: [HealthFood]) async {
        guard let store, !foods.isEmpty,
            store.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed)) == .sharingAuthorized
        else { return }
        await foodWrites.run(foods.map(\.id)) {
            await Self.removeFoods(ids: foods.map(\.id), from: store)
            await Self.writeFoods(foods, to: store)
        }
    }

    /// Deletes foods saved under these ids, with their samples, after any save of them still on its way.
    public func deleteFoods(ids: [UUID]) async {
        guard let store, !ids.isEmpty else { return }
        await foodWrites.run(ids) { await Self.removeFoods(ids: ids, from: store) }
    }

    private static func writeFoods(_ foods: [HealthFood], to store: HKHealthStore) async {
        let correlations: [HKCorrelation] = foods.compactMap { food in
            var samples = Set<HKSample>()
            for (type, key, value) in HealthTypes.dietaryValues(food.nutrients, micros: food.micros) where value > 0 {
                guard store.authorizationStatus(for: type.type) == .sharingAuthorized else { continue }
                samples.insert(
                    HKQuantitySample(
                        type: type.type, quantity: HKQuantity(unit: type.unit, doubleValue: value),
                        start: food.date, end: food.date,
                        metadata: [
                            HKMetadataKeySyncIdentifier: HealthTypes.syncIdentifier(food.id, key: key),
                            HKMetadataKeySyncVersion: food.version,
                            HKMetadataKeyFoodType: food.name,
                        ]))
            }
            guard !samples.isEmpty else { return nil }
            return HKCorrelation(
                type: HKCorrelationType(.food), start: food.date, end: food.date, objects: samples,
                metadata: [
                    HKMetadataKeySyncIdentifier: food.id.uuidString,
                    HKMetadataKeySyncVersion: food.version,
                    HKMetadataKeyFoodType: food.name,
                ])
        }
        guard !correlations.isEmpty else { return }
        try? await store.save(correlations)
    }

    /// Each dietary type's samples by its own sync ids ("<id>.<key>"), every type at once: they don't
    /// depend on each other, and one after another they're dozens of round trips to Health.
    private static func removeFoods(ids: [UUID], from store: HKHealthStore) async {
        await withTaskGroup(of: Void.self) { group in
            for type in HealthTypes.dietary {
                group.addTask {
                    let predicate = HKQuery.predicateForObjects(
                        withMetadataKey: HKMetadataKeySyncIdentifier,
                        allowedValues: ids.map { HealthTypes.syncIdentifier($0, key: type.key) })
                    _ = try? await store.deleteObjects(of: type.type, predicate: predicate)
                }
            }
        }
    }
}

extension HealthTypes {
    struct Dietary: Sendable {
        var type: HKQuantityType
        var unit: HKUnit
        var key: String
    }

    static let dietary: [Dietary] = [
        Dietary(type: HKQuantityType(.dietaryEnergyConsumed), unit: .kilocalorie(), key: "kcal"),
        Dietary(type: HKQuantityType(.dietaryProtein), unit: .gram(), key: "protein"),
        Dietary(type: HKQuantityType(.dietaryCarbohydrates), unit: .gram(), key: "carbs"),
        Dietary(type: HKQuantityType(.dietaryFatTotal), unit: .gram(), key: "fat"),
        Dietary(type: HKQuantityType(.dietaryFiber), unit: .gram(), key: "fiber"),
        Dietary(type: HKQuantityType(.dietarySugar), unit: .gram(), key: "sugar"),
        Dietary(type: HKQuantityType(.dietaryFatSaturated), unit: .gram(), key: "satFat"),
        Dietary(type: HKQuantityType(.dietarySodium), unit: .gramUnit(with: .milli), key: "sodium"),
        // Vitamins, minerals and fat parts, keyed like the catalogs.
        Dietary(type: HKQuantityType(.dietaryFatMonounsaturated), unit: .gram(), key: "monounsaturatedFat"),
        Dietary(type: HKQuantityType(.dietaryFatPolyunsaturated), unit: .gram(), key: "polyunsaturatedFat"),
        Dietary(type: HKQuantityType(.dietaryCholesterol), unit: .gramUnit(with: .milli), key: "cholesterol"),
        Dietary(type: HKQuantityType(.dietaryPotassium), unit: .gramUnit(with: .milli), key: "potassium"),
        Dietary(type: HKQuantityType(.dietaryCalcium), unit: .gramUnit(with: .milli), key: "calcium"),
        Dietary(type: HKQuantityType(.dietaryIron), unit: .gramUnit(with: .milli), key: "iron"),
        Dietary(type: HKQuantityType(.dietaryMagnesium), unit: .gramUnit(with: .milli), key: "magnesium"),
        Dietary(type: HKQuantityType(.dietaryPhosphorus), unit: .gramUnit(with: .milli), key: "phosphorus"),
        Dietary(type: HKQuantityType(.dietaryZinc), unit: .gramUnit(with: .milli), key: "zinc"),
        Dietary(type: HKQuantityType(.dietaryCopper), unit: .gramUnit(with: .milli), key: "copper"),
        Dietary(type: HKQuantityType(.dietaryManganese), unit: .gramUnit(with: .milli), key: "manganese"),
        Dietary(type: HKQuantityType(.dietarySelenium), unit: .gramUnit(with: .micro), key: "selenium"),
        Dietary(type: HKQuantityType(.dietaryVitaminA), unit: .gramUnit(with: .micro), key: "vitaminA"),
        Dietary(type: HKQuantityType(.dietaryVitaminC), unit: .gramUnit(with: .milli), key: "vitaminC"),
        Dietary(type: HKQuantityType(.dietaryVitaminD), unit: .gramUnit(with: .micro), key: "vitaminD"),
        Dietary(type: HKQuantityType(.dietaryVitaminE), unit: .gramUnit(with: .milli), key: "vitaminE"),
        Dietary(type: HKQuantityType(.dietaryVitaminK), unit: .gramUnit(with: .micro), key: "vitaminK"),
        Dietary(type: HKQuantityType(.dietaryThiamin), unit: .gramUnit(with: .milli), key: "thiamin"),
        Dietary(type: HKQuantityType(.dietaryRiboflavin), unit: .gramUnit(with: .milli), key: "riboflavin"),
        Dietary(type: HKQuantityType(.dietaryNiacin), unit: .gramUnit(with: .milli), key: "niacin"),
        Dietary(type: HKQuantityType(.dietaryPantothenicAcid), unit: .gramUnit(with: .milli), key: "pantothenicAcid"),
        Dietary(type: HKQuantityType(.dietaryVitaminB6), unit: .gramUnit(with: .milli), key: "vitaminB6"),
        Dietary(type: HKQuantityType(.dietaryFolate), unit: .gramUnit(with: .micro), key: "folate"),
        Dietary(type: HKQuantityType(.dietaryVitaminB12), unit: .gramUnit(with: .micro), key: "vitaminB12"),
        Dietary(type: HKQuantityType(.dietaryCaffeine), unit: .gramUnit(with: .milli), key: "caffeine"),
        // Millilitres: a glass of water on its own, or the fluid in a drink logged as food.
        Dietary(type: HKQuantityType(.dietaryWater), unit: .literUnit(with: .milli), key: "water"),
    ]

    /// The sync id of a food's sample of one dietary type.
    static func syncIdentifier(_ id: UUID, key: String) -> String { "\(id.uuidString).\(key)" }

    static func dietaryValues(_ n: Nutrients, micros: [String: Double] = [:]) -> [(Dietary, String, Double)] {
        var values: [String: Double?] = [
            "kcal": n.kcal, "protein": n.protein, "carbs": n.carbs, "fat": n.fat, "fiber": n.fiber,
            "sugar": n.sugar, "satFat": n.saturatedFat, "sodium": n.sodium,
        ]
        for (key, value) in micros where values[key] == nil { values[key] = value }
        return dietary.compactMap { d in (values[d.key] ?? nil).map { (d, d.key, $0) } }
    }
}
#endif
