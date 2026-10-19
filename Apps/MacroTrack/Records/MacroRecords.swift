import Foundation
import NutritionEngine
import SystemCore
import SystemStore

// The records every Macro Track device reads and writes, compiled into the iPhone, iPad, Mac and
// Vision Pro app and the Watch app alike, so they agree on kinds and versions. Records that need the
// food catalog or the meal planner stay in the app (StoredRecords.swift). Kinds never change once
// shipped; bump a schemaVersion (and teach `migrate`) when a record's shape changes.

nonisolated extension MacroSettings: @retroactive StoredRecord {
    public static var kind: String { "settings" }
    public static var schemaVersion: Int { 1 }

    /// The id new settings get, so two devices that set up before syncing save one record. Settings
    /// made before it have a random id; `MacroSettings.inForce` picks between records when there are two.
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
