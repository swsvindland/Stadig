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
    /// `revision(of:)` says which kinds moved.
    public private(set) var revision: Int = 0
    /// Where the data lives, in words: "iCloud", "This device only" or "Memory only".
    public private(set) var syncStatus: String

    private let name: String
    private let container: ModelContainer?
    private let storeURL: URL?
    /// Who this instance's saves are by in the store's history. The remote-change notification fires
    /// for every save, this process's own included, so this is how a refresh tells CloudKit's
    /// changes (and another process's) from the echo of a save it already accounted for.
    private let author: String
    @ObservationIgnored private var context: ModelContext?
    /// Decoded `all` results by record kind. A local write clears only its own kind, so saving a
    /// setting doesn't re-decode every photo; an erase or a remote change clears them all.
    @ObservationIgnored private var cache: [String: Any] = [:]
    /// The `revision` at which each kind last changed, and at which every kind did (an erase or a
    /// remote change).
    @ObservationIgnored private var kindRevisions: [String: Int] = [:]
    @ObservationIgnored private var everyKindRevision = 0
    @ObservationIgnored private var remoteObserver: NotificationObservation?
    @ObservationIgnored private var remoteRefresh: Task<Void, Never>?
    @ObservationIgnored private var remoteChangeNoticed: ContinuousClock.Instant?
    /// The newest history transaction already accounted for.
    @ObservationIgnored private var historyToken: DefaultHistoryToken?
    @ObservationIgnored private var changeObservers: [WeakChangeObservation] = []

    /// A burst of remote-change notifications (a CloudKit import posts several) waits for this much
    /// quiet before refreshing, but never longer than `remoteMaxDelay` after the first, so a long
    /// import still shows up as it lands.
    static let remoteQuietPeriod: Duration = .milliseconds(250)
    static let remoteMaxDelay: Duration = .seconds(1)
    private static let rowEntity = Schema.entityName(for: RecordRow.self)

    /// `cloudKitContainer`: e.g. "iCloud.dev.svindland.stadig.lift"; nil or `inMemory` keeps the data on
    /// this device only. If the CloudKit store can't open, falls back to a local store at the same
    /// file, then to memory, logging why. Never crashes.
    public convenience init(name: String, cloudKitContainer: String?, inMemory: Bool = false) {
        self.init(name: name, cloudKitContainer: cloudKitContainer, inMemory: inMemory, directory: nil)
    }

    /// `directory` overrides where the store file goes (Application Support/SystemStore by default).
    init(name: String, cloudKitContainer: String?, inMemory: Bool, directory: URL?) {
        self.name = name
        let author = "RecordStore-\(UUID().uuidString)"
        self.author = author
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
        context = opened.map { Self.makeContext($0.container, author: author) }

        if let opened {
            if opened.status != candidates.first?.status {
                storeLog.notice("\(name, privacy: .public): fell back to \(opened.status, privacy: .public)")
            }
        } else {
            storeLog.fault("\(name, privacy: .public): no store could be opened; reads are empty and writes are dropped")
        }

        if storeURL != nil {
            historyToken = newestHistoryToken()
            // NSPersistentStoreRemoteChangeNotification, with the store's URL under NSPersistentStoreURLKey
            // ("storeURL"): posted when CloudKit imports changes, when another process writes the
            // store, and after this store's own saves (which the refresh tells apart by author).
            let token = NotificationCenter.default.addObserver(
                forName: Notification.Name("NSPersistentStoreRemoteChangeNotification"), object: nil, queue: .main
            ) { [weak self] note in
                let changedURL = note.userInfo?["storeURL"] as? URL
                MainActor.assumeIsolated { self?.storeChangedRemotely(at: changedURL) }
            }
            remoteObserver = NotificationObservation(token)
        }
    }

    // MARK: Observing

    /// The `revision` at which records of this type last changed: a local save, delete or import of
    /// the kind, an erase, or a remote change (which may touch any kind). An app model can skip
    /// re-reading the kinds that didn't move.
    public func revision<T: StoredRecord>(of type: T.Type) -> Int {
        _ = revision
        return max(kindRevisions[T.kind] ?? 0, everyKindRevision)
    }

    /// Calls `handler` on the main actor when changes made elsewhere arrive (CloudKit importing
    /// another device's edits, or another process writing the store), once per burst, after
    /// `revision` has moved and the caches are cleared. This store's own writes don't call it: the
    /// caller made them and knows. Keep the returned token alive; releasing it stops the calls.
    public func observeChanges(_ handler: @escaping @MainActor @Sendable () -> Void) -> AnyObject {
        let observation = RecordStoreObservation(handler)
        changeObservers.removeAll { $0.observation == nil }
        changeObservers.append(WeakChangeObservation(observation: observation))
        return observation
    }

    // MARK: Reading

    /// Every live record of a type: decoded, migrated if stored at an older schema version,
    /// de-duplicated by id keeping the newest `updatedAt`, deletions excluded. Newest first. Records
    /// written by a newer app version (a schema version this type doesn't know) are left out.
    public func all<T: StoredRecord>(_ type: T.Type) -> [T] {
        _ = revision
        if let cached = cache[T.kind] as? [T] { return cached }

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
        cache[T.kind] = records
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
                // A save in a deletion's own millisecond wins, unlike in `precedes`: it was made after
                // the delete (an edit made before it is stamped earlier), as when Macro Track's
                // `setState` deletes a day's status and saves it again under the same id. Writing it
                // into every row of the record replaces the tombstone, so other devices agree.
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
        commit(changes, kind: T.kind, context)
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
        commit(write(tombstone, into: rows, context: context).changed ? 1 : 0, kind: T.kind, context)
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
        changed(kinds: nil)
    }

    // MARK: Backup

    /// The whole database (one entry per record, deletions included so they carry over) plus every
    /// file in the shared container, as a readable `BackupFile` JSON.
    public func exportBackup(app: AppID, shared: SharedContainer?) throws -> Data {
        try Self.writeBackup(app: app, records: backupRecords(), shared: shared)
    }

    /// `exportBackup`, encoding off the main actor: for a store with years of records the JSON takes
    /// seconds. Only reading the rows happens here.
    public func exportBackup(app: AppID, shared: SharedContainer?) async throws -> Data {
        let records = try backupRecords()
        return try await Self.writeBackupDetached(app: app, records: records, shared: shared)
    }

    /// Merges a backup into the store: for each record the newest `updatedAt` wins (a deletion in
    /// the backup that is newer than the stored copy deletes it). Payloads keep their schema version
    /// and are migrated whenever they're read, so a backup from an older app version restores. Shared
    /// files merge the same way (see `SharedContainer.restore`). Throws, changing nothing, if the data
    /// isn't a backup, was written by another app than `app` (record kinds like "settings" and
    /// "session" mean different things in each app), comes from a newer app version, or names an
    /// invalid shared path. If writing the shared files fails after the records were saved, that
    /// error is thrown with the records already restored and `revision` moved, so reload either way.
    ///
    /// The summary counts what changed: live records restored or updated, by kind, and shared files written.
    @discardableResult
    public func importBackup(_ data: Data, app: AppID, shared: SharedContainer?) throws -> BackupSummary {
        try restore(BackupFile(data: data), app: app, shared: shared)
    }

    /// `importBackup`, reading the file off the main actor first: the JSON is the slow part of a big
    /// backup. The merge itself runs here.
    @discardableResult
    public func importBackup(_ data: Data, app: AppID, shared: SharedContainer?) async throws -> BackupSummary {
        let file = try await Self.readBackupDetached(data)
        return try restore(file, app: app, shared: shared)
    }

    private func backupRecords() throws -> [BackupRecord] {
        guard let context else { throw SystemStoreError.storeUnavailable }
        var newest: [RowKey: RecordVersion] = [:]
        for row in try context.fetch(FetchDescriptor<RecordRow>()) {
            let version = RecordVersion(row)
            let key = RowKey(kind: row.kind, uuid: row.uuid)
            if let current = newest[key], !current.precedes(version) { continue }
            newest[key] = version
        }
        return newest.values
            .sorted { ($0.kind, $0.updatedAt, $0.uuid.uuidString) < ($1.kind, $1.updatedAt, $1.uuid.uuidString) }
            .map(BackupRecord.init)
    }

    nonisolated private static func writeBackup(app: AppID, records: [BackupRecord], shared: SharedContainer?) throws -> Data {
        let file = BackupFile(app: app, created: Date(), records: records, shared: shared?.allFiles() ?? [:])
        return try SystemJSON.encoder(pretty: true).encode(file)
    }

    /// `@concurrent`, so it runs on the global executor rather than the caller's (main) actor, also
    /// if the package turns on nonisolated(nonsending) by default.
    @concurrent nonisolated private static func writeBackupDetached(app: AppID, records: [BackupRecord],
                                                                    shared: SharedContainer?) async throws -> Data {
        try writeBackup(app: app, records: records, shared: shared)
    }

    @concurrent nonisolated private static func readBackupDetached(_ data: Data) async throws -> BackupFile {
        try BackupFile(data: data)
    }

    private func restore(_ file: BackupFile, app: AppID, shared: SharedContainer?) throws -> BackupSummary {
        guard file.app == app else { throw SystemStoreError.backupFromOtherApp(file.app) }
        guard let context else { throw SystemStoreError.storeUnavailable }
        if let shared { try shared.validate(paths: file.shared.keys) }

        var rowsByKey = Dictionary(grouping: try context.fetch(FetchDescriptor<RecordRow>())) { RowKey(kind: $0.kind, uuid: $0.uuid) }
        var summary = BackupSummary()
        var changedKinds: Set<String> = []
        for record in file.records {
            let incoming = RecordVersion(record)
            let key = RowKey(kind: record.kind, uuid: record.uuid)
            let rows = rowsByKey[key] ?? []
            if let current = Self.newest(rows).map(RecordVersion.init), !current.precedes(incoming) { continue }
            let result = write(incoming, into: rows, context: context)
            rowsByKey[key] = result.rows
            guard result.changed else { continue }
            changedKinds.insert(incoming.kind)
            if !incoming.deleted {
                summary.records += 1
                summary.kinds[incoming.kind, default: 0] += 1
            }
        }
        if !changedKinds.isEmpty {
            do {
                try context.save()
            } catch {
                context.rollback()
                changed(kinds: changedKinds)
                throw error
            }
            // Before the shared files, so a failure writing them can't leave the records saved but
            // the caches and `revision` saying they aren't.
            changed(kinds: changedKinds)
        }
        if let shared, !file.shared.isEmpty {
            summary.sharedFiles = try shared.merge(file.shared)
        }
        storeLog.notice("\(self.name, privacy: .public): imported a backup from \(file.app.rawValue, privacy: .public): \(summary.records) records, \(summary.sharedFiles) shared files")
        return summary
    }

    // MARK: Internals

    private static func makeContext(_ container: ModelContainer, author: String) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.author = author
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

    private func commit(_ changes: Int, kind: String, _ context: ModelContext) {
        guard changes > 0 else { return }
        do {
            try context.save()
        } catch {
            storeLog.error("\(self.name, privacy: .public): save failed: \(String(describing: error), privacy: .public)")
            context.rollback()
        }
        changed(kinds: [kind])
    }

    /// Records that `kinds` changed (nil: every kind), dropping their decoded caches.
    private func changed(kinds: Set<String>?) {
        revision += 1
        if let kinds {
            for kind in kinds {
                cache[kind] = nil
                kindRevisions[kind] = revision
            }
        } else {
            cache.removeAll()
            kindRevisions.removeAll()
            everyKindRevision = revision
        }
    }

    /// Coalesces a burst of remote-change notifications into one refresh (see `remoteQuietPeriod`).
    func storeChangedRemotely(at url: URL?) {
        if let url, let storeURL,
           url.resolvingSymlinksInPath().standardizedFileURL != storeURL.resolvingSymlinksInPath().standardizedFileURL { return }
        let now = ContinuousClock.now
        let first = remoteChangeNoticed ?? now
        remoteChangeNoticed = first
        remoteRefresh?.cancel()
        let deadline = min(now + Self.remoteQuietPeriod, first + Self.remoteMaxDelay)
        remoteRefresh = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.refreshAfterRemoteChange()
        }
    }

    /// When the store holds changes this instance didn't make: a fresh context, so no stale object
    /// survives, every cache cleared, a revision bump and the observers told. The echo of this
    /// store's own saves changes nothing; they were accounted for when they were made.
    private func refreshAfterRemoteChange() {
        remoteRefresh = nil
        remoteChangeNoticed = nil
        let newest = newestHistoryToken()
        let foreign = hasForeignChanges(since: historyToken)
        historyToken = newest ?? historyToken
        guard foreign else { return }
        if let container { context = Self.makeContext(container, author: author) }
        changed(kinds: nil)
        changeObservers.removeAll { $0.observation == nil }
        for observer in changeObservers {
            observer.observation?.handler()
        }
    }

    private func newestHistoryToken() -> DefaultHistoryToken? {
        guard let context else { return nil }
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>(sortBy: [SortDescriptor(\.transactionIdentifier, order: .reverse)])
        descriptor.fetchLimit = 1
        do {
            return try context.fetchHistory(descriptor).first?.token
        } catch {
            storeLog.error("\(self.name, privacy: .public): couldn't read the store's history: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Whether a transaction after `token` by anyone but this instance changed a record row; one that
    /// only touches CloudKit's bookkeeping doesn't count. The nil check is spelled out because the
    /// predicate runs as SQL, where `author != x` is false for a NULL author.
    private func hasForeignChanges(since token: DefaultHistoryToken?) -> Bool {
        guard let context else { return false }
        let author = self.author
        let predicate: Predicate<DefaultHistoryTransaction>
        if let token {
            predicate = #Predicate { $0.token > token && ($0.author == nil || $0.author != author) }
        } else {
            predicate = #Predicate { $0.author == nil || $0.author != author }
        }
        do {
            return try context.fetchHistory(HistoryDescriptor(predicate: predicate)).contains { transaction in
                transaction.changes.contains { $0.changedPersistentIdentifier.entityName == Self.rowEntity }
            }
        } catch {
            // Can't tell whose they are: refresh, the safe side.
            storeLog.error("\(self.name, privacy: .public): couldn't read the store's history: \(String(describing: error), privacy: .public)")
            return true
        }
    }

    // MARK: Test hooks

    /// Inserts a row exactly as given, the way a CloudKit import or an older app version would.
    func insertRawRow(kind: String, uuid: UUID, updatedAt: Date, schemaVersion: Int, payload: Data, deleted: Bool = false) {
        guard let context else { return }
        context.insert(RecordRow(kind: kind, uuid: uuid, updatedAt: updatedAt, schemaVersion: schemaVersion,
                                 payload: payload, deleted: deleted))
        commit(1, kind: kind, context)
    }

    func rows(kind: String) -> [RecordRow] { fetchRows(kind: kind) }

    var storeFileURL: URL? { storeURL }
}

struct RowKey: Hashable {
    var kind: String
    var uuid: UUID
}

/// A `RecordStore.observeChanges` registration; the store holds it weakly, so releasing it ends the calls.
final class RecordStoreObservation {
    let handler: @MainActor @Sendable () -> Void

    init(_ handler: @escaping @MainActor @Sendable () -> Void) { self.handler = handler }
}

struct WeakChangeObservation {
    weak var observation: RecordStoreObservation?
}

/// Removes a NotificationCenter block observer when released.
final class NotificationObservation {
    private let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol) { self.token = token }

    deinit { NotificationCenter.default.removeObserver(token) }
}
