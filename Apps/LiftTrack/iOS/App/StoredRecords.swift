import Foundation
import LiftEngine
import SystemCore
import SystemStore

// Stadig Lift's records in its own CloudKit-synced database. Kinds never change once shipped;
// bump a schemaVersion (and teach `migrate`) when a record's shape changes.
//
// SessionRecord also lives unversioned in the Watch's outbox.json, and LiveSession in its
// session.json (and in the phone's live-session.json): a shape change there must stay decodable from
// the old JSON (new fields Optional, or read with decodeIfPresent). The Watch sets an undecodable file
// aside rather than overwriting it, but it can't migrate one.

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
    /// Still 1 with exercises' own steps (`exerciseSteps`), which read as none when absent. A gym is
    /// only saved when the person edits it, so a version that doesn't know them loses them only on
    /// an edit made there; a bump would leave that version on a stand-in full gym until it updates.
    public static var schemaVersion: Int { 1 }
}

nonisolated extension Mesocycle: @retroactive StoredRecord {
    public static var kind: String { "mesocycle" }
    /// 2 added the block's focus, which the next block takes turns from: a version that only knows
    /// 1 would drop it when it saved the block, so it leaves these out. 1 reads as no focus.
    public static var schemaVersion: Int { 2 }
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
    public static var schemaVersion: Int { 2 }

    /// 2 measures hips at the hip bones and glutes at the widest point, where "hips" was taken
    /// before, so older hip readings move to glutes.
    public static func migrate(_ json: inout [String: Any], from version: Int) throws {
        if version == 1, var measurements = json["measurements"] as? [String: Any], let hips = measurements.removeValue(forKey: "hipsCm") {
            measurements["glutesCm"] = hips
            json["measurements"] = measurements
        }
    }
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
    /// 2 added the period's `deletedAt` (a delete is a tombstone that syncs): a version that only
    /// knows 1 would read a deleted period as live, so it leaves these out. 1 needs no change.
    public static var schemaVersion: Int { 2 }
}

nonisolated extension ProfileRecord: @retroactive StoredRecord {
    public static var kind: String { "profile" }
    public static var schemaVersion: Int { 1 }
}
