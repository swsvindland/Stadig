import CryptoKit
import FoodDatabase
import Foundation
import MealPlanner
import NutritionEngine
import SystemCore
import SystemStore

// Macro Track's records in its own CloudKit-synced database. Kinds never change once shipped;
// bump a schemaVersion (and teach `migrate`) when a record's shape changes.

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
    static func id(for foodID: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(foodID.utf8)))
        var bytes = (
            digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7], digest[8], digest[9],
            digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
        )
        bytes.6 = (bytes.6 & 0x0F) | 0x50
        bytes.8 = (bytes.8 & 0x3F) | 0x80
        return UUID(uuid: bytes)
    }
}

nonisolated extension MacroSettings: @retroactive StoredRecord {
    public static var kind: String { "settings" }
    public static var schemaVersion: Int { 1 }

    /// The id new settings get, so two devices that set up before syncing save one record. Settings
    /// made before it have a random id; `AppModel.inForce` picks between records when there are two.
    static let singletonID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x50, 0, 0x80, 0, 0, 0, 0, 0, 0x5E, 0x77))
}

nonisolated extension FoodEntry: @retroactive StoredRecord {
    public static var kind: String { "entry" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension WeighIn: @retroactive StoredRecord {
    public static var kind: String { "weigh-in" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension DayStatus: @retroactive StoredRecord {
    public static var kind: String { "day-status" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension PhasePlan: @retroactive StoredRecord {
    public static var kind: String { "plan" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension CheckIn: @retroactive StoredRecord {
    public static var kind: String { "check-in" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension CustomFoodRecord: StoredRecord {
    static var kind: String { "custom-food" }
    static var schemaVersion: Int { 1 }
}

nonisolated extension FavoriteRecord: StoredRecord {
    static var kind: String { "favorite" }
    static var schemaVersion: Int { 1 }
}

nonisolated extension LifeModeRecord: @retroactive StoredRecord {
    public static var kind: String { "life-mode" }
    /// 2 added the period's `deletedAt` (a delete is a tombstone that syncs): a version that only
    /// knows 1 would read a deleted period as live, so it leaves these out. 1 needs no change.
    public static var schemaVersion: Int { 2 }
}

nonisolated extension ProfileRecord: @retroactive StoredRecord {
    public static var kind: String { "profile" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension MealPlan: @retroactive StoredRecord {
    public static var kind: String { "meal-plan" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension Supplement: @retroactive StoredRecord {
    public static var kind: String { "supplement" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension SupplementLog: @retroactive StoredRecord {
    public static var kind: String { "supplement-log" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension WaterLog: @retroactive StoredRecord {
    public static var kind: String { "water" }
    public static var schemaVersion: Int { 1 }
}
