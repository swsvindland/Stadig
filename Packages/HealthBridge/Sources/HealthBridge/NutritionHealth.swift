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
            predicates: [.quantitySample(type: HealthTypes.bodyMass,
                                         predicate: HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate))],
            sortDescriptors: [SortDescriptor(\.endDate)])
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.compactMap { sample in
            let source = sample.sourceRevision.source
            if source.bundleIdentifier.hasAnyPrefix(ownBundlePrefixes) { return nil }
            return HealthWeight(id: sample.uuid, date: sample.endDate, kg: sample.quantity.doubleValue(for: HealthTypes.kg),
                                sourceName: source.name)
        }
    }

    /// Saves (or replaces) a manual weigh-in, keyed by its id.
    public func saveWeight(id: UUID, date: Date, kg: Double, version: Int) async {
        guard let store, store.authorizationStatus(for: HealthTypes.bodyMass) == .sharingAuthorized else { return }
        let sample = HKQuantitySample(type: HealthTypes.bodyMass, quantity: HKQuantity(unit: HealthTypes.kg, doubleValue: kg),
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
    /// nutrient cleared in an edit doesn't linger. One write for the batch.
    public func saveFoods(_ foods: [HealthFood]) async {
        guard let store, !foods.isEmpty,
              store.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed)) == .sharingAuthorized else { return }
        await deleteFoods(ids: foods.map(\.id))
        let correlations: [HKCorrelation] = foods.compactMap { food in
            var samples = Set<HKSample>()
            for (type, key, value) in HealthTypes.dietaryValues(food.nutrients, micros: food.micros) where value > 0 {
                guard store.authorizationStatus(for: type.type) == .sharingAuthorized else { continue }
                samples.insert(HKQuantitySample(type: type.type, quantity: HKQuantity(unit: type.unit, doubleValue: value),
                                                start: food.date, end: food.date, metadata: [
                                                    HKMetadataKeySyncIdentifier: "\(food.id.uuidString).\(key)",
                                                    HKMetadataKeySyncVersion: food.version,
                                                    HKMetadataKeyFoodType: food.name,
                                                ]))
            }
            guard !samples.isEmpty else { return nil }
            return HKCorrelation(type: HKCorrelationType(.food), start: food.date, end: food.date, objects: samples, metadata: [
                HKMetadataKeySyncIdentifier: food.id.uuidString,
                HKMetadataKeySyncVersion: food.version,
                HKMetadataKeyFoodType: food.name,
            ])
        }
        guard !correlations.isEmpty else { return }
        try? await store.save(correlations)
    }

    /// Deletes foods saved under these ids, with their samples.
    public func deleteFoods(ids: [UUID]) async {
        guard let store, !ids.isEmpty else { return }
        let keys = HealthTypes.dietary.map(\.key)
        for type in HealthTypes.dietary {
            let identifiers = ids.flatMap { id in keys.map { "\(id.uuidString).\($0)" } }
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: identifiers)
            _ = try? await store.deleteObjects(of: type.type, predicate: predicate)
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

    static func dietaryValues(_ n: Nutrients, micros: [String: Double] = [:]) -> [(Dietary, String, Double)] {
        var values: [String: Double?] = ["kcal": n.kcal, "protein": n.protein, "carbs": n.carbs, "fat": n.fat, "fiber": n.fiber,
                                         "sugar": n.sugar, "satFat": n.saturatedFat, "sodium": n.sodium]
        for (key, value) in micros where values[key] == nil { values[key] = value }
        return dietary.compactMap { d in (values[d.key] ?? nil).map { (d, d.key, $0) } }
    }
}
#endif
