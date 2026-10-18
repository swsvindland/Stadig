import Foundation
import Observation
import OSLog
import SwiftData
import SystemCore

/// An app's own database: every record kind in one SwiftData model, synced through the app's
/// private CloudKit database when it can be, and readable as plain `StoredRecord` values.
///
/// Newest wins, to the millisecond, everywhere: on save, on import, and when CloudKit has delivered
/// more than one row for the same record. Reads migrate older payloads in memory; a row is only
/// rewritten at the new schema version when the record is next saved, so a device still running the
/// previous app version can keep reading it until then.
@MainActor @Observable
public final class RecordStore {
    static let iCloudStatus = "iCloud"
    static let localStatus = "This device only"
    static let memoryStatus = "Memory only"

    /// Bumps on every local change (save, delete, erase, import) and when CloudKit delivers remote
    /// changes. `all` and `get` read it, so a SwiftUI view that calls them re-renders on its own.
    public private(set) var revision: Int = 0
    /// Where the data lives, in words: "iCloud", "This device only" or "Memory only".
    public private(set) var syncStatus: String

    private let name: String
    private let container: ModelContainer?
    private let storeURL: URL?
    @ObservationIgnored private var context: ModelContext?
    /// Decoded `all` results per record type; cleared on every change.
    @ObservationIgnored private var cache: [ObjectIdentifier: Any] = [:]
    @ObservationIgnored private var remoteObserver: NotificationObservation?
    @ObservationIgnored private var remoteRefreshPending = false

    /// `cloudKitContainer`: e.g. "iCloud.dev.svindland.stadig.lift"; nil or `inMemory` keeps the data on
    /// this device only. If the CloudKit store can't open, falls back to a local store at the same
    /// file, then to memory, logging why. Never crashes.
    public convenience init(name: String, cloudKitContainer: String?, inMemory: Bool = false) {
        self.init(name: name, cloudKitContainer: cloudKitContainer, inMemory: inMemory, directory: nil)
    }

    /// `directory` overrides where the store file goes (Application Support/SystemStore by default).
    init(name: String, cloudKitContainer: String?, inMemory: Bool, directory: URL?) {
        self.name = name
        let schema = Schema(versionedSchema: RecordStoreSchemaV1.self)
        var candidates: [(status: String, configuration: ModelConfiguration, url: URL?)] = []
        if !inMemory {
            let folder = directory ?? URL.applicationSupportDirectory.appending(path: "SystemStore", directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appending(path: "\(name).store", directoryHint: .notDirectory)
                if let cloudKitContainer, Bundle.main.bundleIdentifier == nil {
                    // A command-line tool or test runner: CloudKit's push registration asserts on a
                    // missing bundle identifier when the store is torn down, crashing the process.
                    storeLog.notice("\(name, privacy: .public): no bundle identifier, so no CloudKit (\(cloudKitContainer, privacy: .public))")
                } else if let cloudKitContainer {
                    candidates.append((Self.iCloudStatus,
                                       ModelConfiguration(name, schema: schema, url: url, cloudKitDatabase: .private(cloudKitContainer)),
                                       url))
                }
                candidates.append((Self.localStatus, ModelConfiguration(name, schema: schema, url: url, cloudKitDatabase: .none), url))
            } catch {
                storeLog.error("\(name, privacy: .public): can't create \(folder.path(percentEncoded: false), privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        candidates.append((Self.memoryStatus,
                           ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none),
                           nil))

        var opened: (container: ModelContainer, status: String, url: URL?)?
        for candidate in candidates {
            do {
                let container = try ModelContainer(for: schema, migrationPlan: RecordStoreMigrationPlan.self,
                                                   configurations: [candidate.configuration])
                opened = (container, candidate.status, candidate.url)
                break
            } catch {
                storeLog.error("\(name, privacy: .public): couldn't open the \(candidate.status, privacy: .public) store: \(String(describing: error), privacy: .public)")
            }
        }

        container = opened?.container
        storeURL = opened?.url
        syncStatus = opened?.status ?? "Unavailable"
        context = opened.map { Self.makeContext($0.container) }

        if let opened {
            if opened.status != candidates.first?.status {
                storeLog.notice("\(name, privacy: .public): fell back to \(opened.status, privacy: .public)")
            }
        } else {
            storeLog.fault("\(name, privacy: .public): no store could be opened; reads are empty and writes are dropped")
        }

        if storeURL != nil {
            // NSPersistentStoreRemoteChangeNotification, with the store's URL under NSPersistentStoreURLKey
            // ("storeURL"): posted when CloudKit imports changes (and for other writes to the store).
            let token = NotificationCenter.default.addObserver(
                forName: Notification.Name("NSPersistentStoreRemoteChangeNotification"), object: nil, queue: .main
            ) { [weak self] note in
                let changedURL = note.userInfo?["storeURL"] as? URL
                MainActor.assumeIsolated { self?.storeChangedRemotely(at: changedURL) }
            }
            remoteObserver = NotificationObservation(token)
        }
    }

    // MARK: Reading

    /// Every live record of a type: decoded, migrated if stored at an older schema version,
    /// de-duplicated by id keeping the newest `updatedAt`, deletions excluded. Newest first. Records
    /// written by a newer app version (a schema version this type doesn't know) are left out.
    public func all<T: StoredRecord>(_ type: T.Type) -> [T] {
        _ = revision
        let key = ObjectIdentifier(type)
        if let cached = cache[key] as? [T] { return cached }

        var newest: [UUID: RecordVersion] = [:]
        for row in fetchRows(kind: T.kind) {
            let version = RecordVersion(row)
            if let current = newest[row.uuid], !current.precedes(version) { continue }
            newest[row.uuid] = version
        }
        let decoder = SystemJSON.decoder()
        let records = newest.values
            .filter { !$0.deleted }
            .sorted { ($0.updatedAt, $0.uuid.uuidString) > ($1.updatedAt, $1.uuid.uuidString) }
            .compactMap { decode(T.self, $0, decoder) }
        cache[key] = records
        return records
    }

    /// One record, or nil if it doesn't exist, was deleted, or can't be read by this app version.
    public func get<T: StoredRecord>(_ type: T.Type, id: UUID) -> T? {
        _ = revision
        guard let row = Self.newest(fetchRows(kind: T.kind, uuid: id)) else { return nil }
        return decode(T.self, RecordVersion(row), SystemJSON.decoder())
    }

    // MARK: Writing

    /// Upserts by (kind, id). A record older than the stored copy (by `updatedAt`, to the
    /// millisecond) is ignored, as is a write over a copy saved by a newer app version. Set
    /// `updatedAt` to now before saving an edit.
    public func save<T: StoredRecord>(_ record: T) {
        save([record])
    }

    public func save<T: StoredRecord>(_ records: [T]) {
        guard let context, !records.isEmpty else { return }
        let encoder = SystemJSON.encoder()
        let bulk = records.count > 32
        var rowsByID: [UUID: [RecordRow]] = bulk ? Dictionary(grouping: fetchRows(kind: T.kind), by: \.uuid) : [:]
        var changes = 0
        for record in records {
            var stamped = record
            stamped.updatedAt = record.updatedAt.roundedToMilliseconds
            let payload: Data
            do {
                payload = try encoder.encode(stamped)
            } catch {
                storeLog.error("Couldn't encode \(T.kind, privacy: .public) \(record.id, privacy: .public): \(String(describing: error), privacy: .public)")
                continue
            }
            let rows = rowsByID[record.id] ?? (bulk ? [] : fetchRows(kind: T.kind, uuid: record.id))
            rowsByID[record.id] = rows
            let incoming = RecordVersion(kind: T.kind, uuid: record.id, updatedAt: stamped.updatedAt,
                                         schemaVersion: T.schemaVersion, payload: payload, deleted: false)
            if let current = Self.newest(rows).map(RecordVersion.init) {
                if incoming.updatedAt.wholeMilliseconds < current.updatedAt.wholeMilliseconds {
                    storeLog.debug("Ignored an older \(T.kind, privacy: .public) \(record.id, privacy: .public)")
                    continue
                }
                if !current.deleted && current.schemaVersion > T.schemaVersion {
                    storeLog.notice("Not overwriting \(T.kind, privacy: .public) \(record.id, privacy: .public): stored at schema \(current.schemaVersion), this app knows \(T.schemaVersion)")
                    continue
                }
            }
            let result = write(incoming, into: rows, context: context)
            rowsByID[record.id] = result.rows
            if result.changed { changes += 1 }
        }
        commit(changes, context)
    }

    /// Soft delete: the record's rows keep their place with `deleted` set, the payload cleared and
    /// `updatedAt` moved past the last edit, so the deletion syncs and beats older copies.
    public func delete<T: StoredRecord>(_ type: T.Type, id: UUID) {
        guard let context else { return }
        let rows = fetchRows(kind: T.kind, uuid: id)
        guard let current = Self.newest(rows).map(RecordVersion.init),
              rows.contains(where: { !$0.tombstone || !$0.payload.isEmpty }) else { return }
        let stamp = Date(wholeMilliseconds: max(Date().wholeMilliseconds, current.updatedAt.wholeMilliseconds + 1))
        let tombstone = RecordVersion(kind: T.kind, uuid: id, updatedAt: stamp, schemaVersion: T.schemaVersion,
                                      payload: Data(), deleted: true)
        commit(write(tombstone, into: rows, context: context).changed ? 1 : 0, context)
    }

    /// Removes every row of every kind. With iCloud on, that erases the data on every device.
    public func eraseAll() {
        guard let context else { return }
        do {
            for row in try context.fetch(FetchDescriptor<RecordRow>()) {
                context.delete(row)
            }
            try context.save()
        } catch {
            storeLog.error("\(self.name, privacy: .public): erase failed: \(String(describing: error), privacy: .public)")
            context.rollback()
        }
        changed()
    }

    // MARK: Backup

    /// The whole database (one entry per record, deletions included so they carry over) plus every
    /// file in the shared container, as a readable `BackupFile` JSON.
    public func exportBackup(app: AppID, shared: SharedContainer?) throws -> Data {
        guard let context else { throw SystemStoreError.storeUnavailable }
        var newest: [RowKey: RecordVersion] = [:]
        for row in try context.fetch(FetchDescriptor<RecordRow>()) {
            let version = RecordVersion(row)
            let key = RowKey(kind: row.kind, uuid: row.uuid)
            if let current = newest[key], !current.precedes(version) { continue }
            newest[key] = version
        }
        let records = newest.values
            .sorted { ($0.kind, $0.updatedAt, $0.uuid.uuidString) < ($1.kind, $1.updatedAt, $1.uuid.uuidString) }
            .map(BackupRecord.init)
        let file = BackupFile(app: app, created: Date(), records: records, shared: shared?.allFiles() ?? [:])
        return try SystemJSON.encoder(pretty: true).encode(file)
    }

    /// Merges a backup into the store: for each record the newest `updatedAt` wins (a deletion in
    /// the backup that is newer than the stored copy deletes it). Payloads keep their schema version
    /// and are migrated whenever they're read, so a backup from an older app version restores. Shared
    /// files merge the same way (see `SharedContainer.restore`). Throws, changing nothing, if the data
    /// isn't a backup, comes from a newer app version, or names an invalid shared path.
    ///
    /// The summary counts what changed: live records restored or updated, by kind, and shared files written.
    @discardableResult
    public func importBackup(_ data: Data, shared: SharedContainer?) throws -> BackupSummary {
        let file = try BackupFile(data: data)
        guard let context else { throw SystemStoreError.storeUnavailable }
        if let shared { try shared.validate(paths: file.shared.keys) }

        var rowsByKey = Dictionary(grouping: try context.fetch(FetchDescriptor<RecordRow>())) { RowKey(kind: $0.kind, uuid: $0.uuid) }
        var summary = BackupSummary()
        var changes = 0
        for record in file.records {
            let incoming = RecordVersion(record)
            let key = RowKey(kind: record.kind, uuid: record.uuid)
            let rows = rowsByKey[key] ?? []
            if let current = Self.newest(rows).map(RecordVersion.init), !current.precedes(incoming) { continue }
            let result = write(incoming, into: rows, context: context)
            rowsByKey[key] = result.rows
            guard result.changed else { continue }
            changes += 1
            if !incoming.deleted {
                summary.records += 1
                summary.kinds[incoming.kind, default: 0] += 1
            }
        }
        if changes > 0 {
            do {
                try context.save()
            } catch {
                context.rollback()
                changed()
                throw error
            }
        }
        if let shared, !file.shared.isEmpty {
            summary.sharedFiles = try shared.merge(file.shared)
        }
        if changes > 0 { changed() }
        storeLog.notice("\(self.name, privacy: .public): imported a backup from \(file.app.rawValue, privacy: .public): \(summary.records) records, \(summary.sharedFiles) shared files")
        return summary
    }

    // MARK: Internals

    private static func makeContext(_ container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    /// The row that speaks for a record when CloudKit has delivered more than one.
    private static func newest(_ rows: [RecordRow]) -> RecordRow? {
        rows.max { RecordVersion($0).precedes(RecordVersion($1)) }
    }

    private func fetchRows(kind: String, uuid: UUID? = nil) -> [RecordRow] {
        guard let context else { return [] }
        let descriptor: FetchDescriptor<RecordRow>
        if let uuid {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.kind == kind && $0.uuid == uuid })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.kind == kind })
        }
        do {
            return try context.fetch(descriptor)
        } catch {
            storeLog.error("Couldn't fetch \(kind, privacy: .public) rows: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private func decode<T: StoredRecord>(_ type: T.Type, _ version: RecordVersion, _ decoder: JSONDecoder) -> T? {
        guard !version.deleted else { return nil }
        do {
            return try RecordCoding.decode(T.self, payload: version.payload, schemaVersion: version.schemaVersion, decoder: decoder)
        } catch {
            storeLog.error("Couldn't read \(T.kind, privacy: .public) \(version.uuid, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Writes `version` into every row of its record, so duplicate rows converge, or into a new row.
    private func write(_ version: RecordVersion, into rows: [RecordRow], context: ModelContext) -> (rows: [RecordRow], changed: Bool) {
        guard !rows.isEmpty else {
            let row = RecordRow(kind: version.kind, uuid: version.uuid, updatedAt: version.updatedAt,
                                schemaVersion: version.schemaVersion, payload: version.payload, deleted: version.deleted)
            context.insert(row)
            return ([row], true)
        }
        var changed = false
        for row in rows {
            if row.updatedAt == version.updatedAt && row.schemaVersion == version.schemaVersion
                && row.tombstone == version.deleted && row.payload == version.payload { continue }
            row.updatedAt = version.updatedAt
            row.schemaVersion = version.schemaVersion
            row.payload = version.payload
            row.tombstone = version.deleted
            changed = true
        }
        return (rows, changed)
    }

    private func commit(_ changes: Int, _ context: ModelContext) {
        guard changes > 0 else { return }
        do {
            try context.save()
        } catch {
            storeLog.error("\(self.name, privacy: .public): save failed: \(String(describing: error), privacy: .public)")
            context.rollback()
        }
        changed()
    }

    private func changed() {
        cache.removeAll()
        revision += 1
    }

    /// Coalesces a burst of remote-change notifications (a CloudKit import posts several) into one
    /// refresh: a fresh context, so no stale object survives, and a revision bump.
    func storeChangedRemotely(at url: URL?) {
        if let url, let storeURL,
           url.resolvingSymlinksInPath().standardizedFileURL != storeURL.resolvingSymlinksInPath().standardizedFileURL { return }
        guard !remoteRefreshPending else { return }
        remoteRefreshPending = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            self.remoteRefreshPending = false
            if let container = self.container { self.context = Self.makeContext(container) }
            self.changed()
        }
    }

    // MARK: Test hooks

    /// Inserts a row exactly as given, the way a CloudKit import or an older app version would.
    func insertRawRow(kind: String, uuid: UUID, updatedAt: Date, schemaVersion: Int, payload: Data, deleted: Bool = false) {
        guard let context else { return }
        context.insert(RecordRow(kind: kind, uuid: uuid, updatedAt: updatedAt, schemaVersion: schemaVersion,
                                 payload: payload, deleted: deleted))
        commit(1, context)
    }

    func rows(kind: String) -> [RecordRow] { fetchRows(kind: kind) }

    var storeFileURL: URL? { storeURL }
}

struct RowKey: Hashable {
    var kind: String
    var uuid: UUID
}

/// Removes a NotificationCenter block observer when released.
final class NotificationObservation {
    private let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol) { self.token = token }

    deinit { NotificationCenter.default.removeObserver(token) }
}
