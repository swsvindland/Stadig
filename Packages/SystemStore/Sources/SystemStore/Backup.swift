import Foundation
import SystemCore

/// A full backup: every record in an app's database plus the shared container's files. Portable and
/// readable: record payloads and shared files embed as JSON rather than base64.
public struct BackupFile: Codable, Sendable {
    public static let formatName = "system-backup"
    public static let currentFormatVersion = 1

    /// Always "system-backup".
    public var format: String
    public var formatVersion: Int
    /// The app that wrote the backup.
    public var app: AppID
    public var created: Date
    public var records: [BackupRecord]
    /// Shared-container files by relative path.
    public var shared: [String: Data]

    public init(format: String = BackupFile.formatName, formatVersion: Int = BackupFile.currentFormatVersion, app: AppID,
                created: Date = Date(), records: [BackupRecord], shared: [String: Data] = [:]) {
        self.format = format
        self.formatVersion = formatVersion
        self.app = app
        self.created = created
        self.records = records
        self.shared = shared
    }

    /// Reads a backup, checking it is one and that this app version understands its format. Lets the
    /// app show what's inside (which app, when, how many records) before importing it.
    public init(data: Data) throws {
        struct Header: Decodable {
            var format: String?
            var formatVersion: Int?
        }
        let decoder = SystemJSON.decoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.format == Self.formatName,
              let version = header.formatVersion else { throw SystemStoreError.notABackup }
        guard version <= Self.currentFormatVersion else { throw SystemStoreError.backupFromNewerVersion(formatVersion: version) }
        self = try decoder.decode(BackupFile.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case format, formatVersion, app, created, records, shared
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        app = try container.decode(AppID.self, forKey: .app)
        created = try container.decode(Date.self, forKey: .created)
        records = try container.decodeIfPresent([BackupRecord].self, forKey: .records) ?? []
        shared = try container.decodeIfPresent([String: EmbeddedJSONData].self, forKey: .shared)?.mapValues(\.data) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(app, forKey: .app)
        try container.encode(created, forKey: .created)
        try container.encode(records, forKey: .records)
        try container.encode(shared.mapValues(EmbeddedJSONData.init), forKey: .shared)
    }
}

/// One record in a backup, exactly as its row holds it (schema version included, so it migrates on read).
public struct BackupRecord: Codable, Sendable {
    public var kind: String
    public var uuid: UUID
    public var updatedAt: Date
    public var schemaVersion: Int
    /// The record as SystemJSON. Empty for a deletion.
    public var payload: Data
    public var deleted: Bool

    public init(kind: String, uuid: UUID, updatedAt: Date, schemaVersion: Int, payload: Data, deleted: Bool) {
        self.kind = kind
        self.uuid = uuid
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.deleted = deleted
    }

    init(_ version: RecordVersion) {
        self.init(kind: version.kind, uuid: version.uuid, updatedAt: version.updatedAt, schemaVersion: version.schemaVersion,
                  payload: version.payload, deleted: version.deleted)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, uuid, updatedAt, schemaVersion, payload, deleted
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        uuid = try container.decode(UUID.self, forKey: .uuid)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        payload = try container.decodeIfPresent(EmbeddedJSONData.self, forKey: .payload)?.data ?? Data()
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        if !payload.isEmpty { try container.encode(EmbeddedJSONData(payload), forKey: .payload) }
        try container.encode(deleted, forKey: .deleted)
    }
}

extension RecordVersion {
    init(_ record: BackupRecord) {
        self.init(kind: record.kind, uuid: record.uuid, updatedAt: record.updatedAt, schemaVersion: record.schemaVersion,
                  payload: record.payload, deleted: record.deleted)
    }
}

/// What an import changed.
public struct BackupSummary: Sendable, Equatable {
    /// Live records restored or updated (deletions applied aren't counted).
    public var records: Int
    /// The same, by record kind.
    public var kinds: [String: Int]
    /// Shared-container files written.
    public var sharedFiles: Int

    public init(records: Int = 0, kinds: [String: Int] = [:], sharedFiles: Int = 0) {
        self.records = records
        self.kinds = kinds
        self.sharedFiles = sharedFiles
    }
}
