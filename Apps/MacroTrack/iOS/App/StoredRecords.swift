import CryptoKit
import FoodDatabase
import Foundation
import MealPlanner
import NutritionEngine
import SystemCore
import SystemStore

// Stadig Macro's records of foods (its own, starred catalog foods and corrected ones) and of meal
// plans, which only this app has. The rest, which the Watch app reads and writes too, are in
// Records/MacroRecords.swift. Kinds never change once shipped; bump a schemaVersion (and teach
// `migrate`) when a record's shape changes.

/// A food the person made: from a label photo, or typed in.
nonisolated struct CustomFoodRecord: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var food: Food
    var updatedAt: Date

    init(id: UUID = UUID(), food: Food, updatedAt: Date = Date()) {
        self.id = id
        var food = food
        food.id = Self.foodID(id)
        food.source = food.source == .label ? .label : .custom
        self.food = food
        self.updatedAt = updatedAt
    }

    static func foodID(_ id: UUID) -> String { "custom:\(id.uuidString)" }

    /// The record id inside a food id `foodID(_:)` made; nil for a catalog food's.
    static func recordID(fromFoodID foodID: String) -> UUID? {
        guard foodID.hasPrefix("custom:") else { return nil }
        return UUID(uuidString: String(foodID.dropFirst("custom:".count)))
    }
}

/// A starred food, from any catalog.
nonisolated struct FavoriteRecord: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var foodID: String
    var updatedAt: Date

    init(foodID: String, updatedAt: Date = Date()) {
        id = Self.id(for: foodID)
        self.foodID = foodID
        self.updatedAt = updatedAt
    }

    /// The same food always gets the same record, so starring on two devices can't duplicate it.
    static func id(for foodID: String) -> UUID { stableID(foodID) }
}

/// The person's own numbers for a catalog food whose package says otherwise. The food keeps the
/// catalog's id, so its barcode, searches, favourites, Log Again and the entries already logged
/// all find the corrected food in the catalog's place, and taking the correction away gives the
/// catalog's back.
nonisolated struct FoodCorrection: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var food: Food
    var updatedAt: Date

    init(food: Food, updatedAt: Date = Date()) {
        id = Self.id(for: food.id)
        self.food = food
        self.updatedAt = updatedAt
    }

    /// One record for each catalog food, so correcting it on two devices can't make two.
    static func id(for foodID: String) -> UUID { stableID("correction:\(foodID)") }
}

/// A version-5 UUID from text: the same text always gives the same id.
nonisolated private func stableID(_ text: String) -> UUID {
    let digest = Array(SHA256.hash(data: Data(text.utf8)))
    var bytes = (
        digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7], digest[8], digest[9],
        digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
    )
    bytes.6 = (bytes.6 & 0x0F) | 0x50
    bytes.8 = (bytes.8 & 0x3F) | 0x80
    return UUID(uuid: bytes)
}

nonisolated extension CustomFoodRecord: StoredRecord {
    static var kind: String { "custom-food" }
    static var schemaVersion: Int { 1 }
}

nonisolated extension FavoriteRecord: StoredRecord {
    static var kind: String { "favorite" }
    static var schemaVersion: Int { 1 }
}

nonisolated extension FoodCorrection: StoredRecord {
    static var kind: String { "food-correction" }
    static var schemaVersion: Int { 1 }
}

nonisolated extension MealPlan: @retroactive StoredRecord {
    public static var kind: String { "meal-plan" }
    public static var schemaVersion: Int { 2 }

    /// 2 added one dish for every lunch and dinner (`PlanPreferences.oneDish`); a plan from before
    /// has two.
    public static func migrate(_ json: inout [String: Any], from version: Int) throws {
        if version == 1, var preferences = json["preferences"] as? [String: Any] {
            preferences["oneDish"] = false
            json["preferences"] = preferences
        }
    }
}
