import Foundation
import SwiftData

/// A record type an app keeps in its database. Stored as one encoded JSON payload per row, so a
/// record always syncs whole.
public protocol StoredRecord: Codable, Sendable, Identifiable where ID == UUID {
    /// The row kind, e.g. "session". Unique per record type and never changed once shipped.
    static var kind: String { get }
    /// Bump when the Codable shape changes, and teach `migrate` the step from the previous version.
    static var schemaVersion: Int { get }
    /// Upgrades an older payload's JSON object by one version (from `version` to `version + 1`).
    /// Called once per step, oldest first. Dates in the object are milliseconds since 1970.
    /// Default: no change.
    static func migrate(_ json: inout [String: Any], from version: Int) throws
    /// When this version of the record was made. Newest wins, to the millisecond, on every device.
    var updatedAt: Date { get set }
}

public extension StoredRecord {
    static func migrate(_ json: inout [String: Any], from version: Int) throws {}
}

/// One SwiftData model for every record kind. CloudKit-compatible: every attribute has a default,
/// no unique constraints, no relationships. CloudKit can deliver two rows for the same record (two
/// devices created it before syncing); readers pick the newest.
@Model
public final class RecordRow {
    public internal(set) var kind: String = ""
    public internal(set) var uuid: UUID = UUID()
    public internal(set) var updatedAt: Date = Date.distantPast
    public internal(set) var schemaVersion: Int = 1
    /// The record as SystemJSON. Empty once deleted.
    public internal(set) var payload: Data = Data()
    /// Persisted as `tombstone`: an attribute named `deleted` would collide with the `isDeleted`
    /// state of the Core Data object underneath (KVC key "deleted").
    var tombstone: Bool = false

    /// A soft-deleted record: kept as a row so the deletion syncs.
    public var deleted: Bool { tombstone }

    init(kind: String, uuid: UUID, updatedAt: Date, schemaVersion: Int, payload: Data, deleted: Bool) {
        self.kind = kind
        self.uuid = uuid
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.tombstone = deleted
    }
}

/// The database schema, versioned from day one. Record shapes version inside their payloads
/// (`StoredRecord.schemaVersion`); this versions the row model itself. CloudKit only allows
/// lightweight changes: add attributes with defaults, never remove or rename.
enum RecordStoreSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [RecordRow.self] }
}

enum RecordStoreMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [RecordStoreSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// One version of one record, as a row or a backup holds it.
struct RecordVersion: Sendable {
    var kind: String
    var uuid: UUID
    var updatedAt: Date
    var schemaVersion: Int
    var payload: Data
    var deleted: Bool

    init(kind: String, uuid: UUID, updatedAt: Date, schemaVersion: Int, payload: Data, deleted: Bool) {
        self.kind = kind
        self.uuid = uuid
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.deleted = deleted
    }

    init(_ row: RecordRow) {
        self.init(kind: row.kind, uuid: row.uuid, updatedAt: row.updatedAt, schemaVersion: row.schemaVersion,
                  payload: row.payload, deleted: row.tombstone)
    }

    /// True when `self` loses to `other` as the copy that speaks for a record: older to the
    /// millisecond, then a live copy before a deletion, then the lower schema version, then the
    /// payload bytes. Total, so every device picks the same winner from the same rows.
    func precedes(_ other: RecordVersion) -> Bool {
        let mine = updatedAt.wholeMilliseconds, theirs = other.updatedAt.wholeMilliseconds
        if mine != theirs { return mine < theirs }
        if deleted != other.deleted { return !deleted }
        if schemaVersion != other.schemaVersion { return schemaVersion < other.schemaVersion }
        return payload.lexicographicallyPrecedes(other.payload)
    }
}

enum RecordCoding {
    /// Decodes a payload, running the type's migrations step by step when it was stored at an older
    /// schema version. A payload from a newer version than the type knows throws.
    static func decode<T: StoredRecord>(_ type: T.Type, payload: Data, schemaVersion: Int,
                                        decoder: JSONDecoder) throws -> T {
        guard schemaVersion <= T.schemaVersion else {
            throw SystemStoreError.newerRecordSchema(kind: T.kind, stored: schemaVersion, known: T.schemaVersion)
        }
        guard schemaVersion < T.schemaVersion else { return try decoder.decode(T.self, from: payload) }
        guard var json = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw SystemStoreError.payloadNotAnObject(kind: T.kind)
        }
        for version in schemaVersion..<T.schemaVersion {
            try T.migrate(&json, from: version)
        }
        return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
