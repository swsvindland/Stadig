import Foundation
import LiftEngine
import SystemCore
import SystemStore

// Lift Track's records in its own CloudKit-synced database. Kinds never change once shipped;
// bump a schemaVersion (and teach `migrate`) when a record's shape changes.

nonisolated extension LiftSettings: @retroactive StoredRecord {
    public static var kind: String { "settings" }
    public static var schemaVersion: Int { 2 }

    /// 2 added the person's focus areas.
    public static func migrate(_ json: inout [String: Any], from version: Int) throws {
        if version == 1 { json["focus"] = [String]() }
    }
}

nonisolated extension Gym: @retroactive StoredRecord {
    public static var kind: String { "gym" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension Mesocycle: @retroactive StoredRecord {
    public static var kind: String { "mesocycle" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension SessionRecord: @retroactive StoredRecord {
    public static var kind: String { "session" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension ActivityRecord: @retroactive StoredRecord {
    public static var kind: String { "activity" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension MeasurementRecord: @retroactive StoredRecord {
    public static var kind: String { "measurement" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension ProgressPhoto: @retroactive StoredRecord {
    public static var kind: String { "photo" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension MobilityRecord: @retroactive StoredRecord {
    public static var kind: String { "mobility" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension BenchmarkRecord: @retroactive StoredRecord {
    public static var kind: String { "benchmark" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension LifeModeRecord: @retroactive StoredRecord {
    public static var kind: String { "life-mode" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension ProfileRecord: @retroactive StoredRecord {
    public static var kind: String { "profile" }
    public static var schemaVersion: Int { 1 }
}
