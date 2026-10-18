import Foundation
import notify
import OSLog
import SystemCore

/// The shared App Group container: small JSON files, each in a versioned envelope
/// `{schemaVersion, writtenBy, writtenAt, payload}`, that the apps and the hub publish for each other.
/// Synchronous, coordinated file IO; the files are small.
public struct SharedContainer: Sendable {
    public static let groupID = "group.dev.svindland.stadig"
    /// The Darwin notification posted after every write, so other apps (and widgets) can reload.
    public static let changeNotification = "dev.svindland.stadig.changed"

    /// Where the files live: `SystemShared` inside the App Group, or the fallback.
    public let directory: URL
    /// False when the App Group isn't available and the fallback directory is in use.
    public let isAppGroup: Bool

    /// Uses the App Group directory; falls back to `fallbackDirectory` (or Application
    /// Support/SystemShared) when the group isn't available (no entitlement, tests). On macOS the
    /// group is only trusted inside the App Sandbox: outside it the system hands back a path even
    /// without the entitlement, and touching another app's group container prompts the user.
    public init(groupID: String = SharedContainer.groupID, fallbackDirectory: URL? = nil) {
        if let group = Self.appGroupDirectory(groupID) {
            directory = group
            isAppGroup = true
        } else {
            let fallback = fallbackDirectory
                ?? URL.applicationSupportDirectory.appending(path: "SystemShared", directoryHint: .isDirectory)
            directory = fallback
            isAppGroup = false
            storeLog.info("App Group \(groupID, privacy: .public) unavailable; sharing through \(fallback.path(percentEncoded: false), privacy: .public)")
        }
    }

    private static func appGroupDirectory(_ groupID: String) -> URL? {
        #if os(macOS)
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil else { return nil }
        #endif
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        // A subfolder, so backups never sweep up the group's Library (preferences, caches).
        let directory = group.appending(path: "SystemShared", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            storeLog.error("App Group \(groupID, privacy: .public) isn't writable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: Reading

    /// The payload at `key`, migrated if it was written with an older schema. Nil if there's no file,
    /// it can't be read, or it was written with a newer schema than the key knows.
    public func read<T>(_ key: SharedKey<T>) -> T? {
        envelope(key)?.payload
    }

    /// The whole envelope at `key` (who wrote it and when), migrated to the key's schema version.
    public func envelope<T>(_ key: SharedKey<T>) -> SharedEnvelope<T>? {
        guard let url = try? fileURL(key.path), let data = coordinatedRead(url) else { return nil }
        do {
            return try key.decodeEnvelope(data)
        } catch {
            storeLog.error("Couldn't read \(key.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: Writing

    /// Writes `value` atomically under file coordination, then posts `changeNotification`. Refuses,
    /// with `SystemStoreError.newerSharedSchema`, when the file on disk was written with a newer
    /// schema than the key knows, rather than overwrite data this app version doesn't understand.
    public func write<T>(_ value: T, to key: SharedKey<T>, by app: AppID) throws {
        let envelope = SharedEnvelope(schemaVersion: key.schemaVersion, writtenBy: app, writtenAt: Date(), payload: value)
        let data = try SystemJSON.encoder().encode(envelope)
        let url = try fileURL(key.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinatedWrite(url, options: .forReplacing) { url in
            if let existing = try? Data(contentsOf: url), let header = EnvelopeHeader.read(existing),
               header.schemaVersion > key.schemaVersion {
                throw SystemStoreError.newerSharedSchema(path: key.path, onDisk: header.schemaVersion, known: key.schemaVersion)
            }
            try data.write(to: url, options: .atomic)
        }
        Self.postChange()
    }

    /// `write`, skipped when the file at `key` already holds the same content, so readers aren't woken
    /// and the payload's own "updated" stamp keeps saying when the content last changed. `carryOver`
    /// copies the stamps that don't count as content from the file on disk into the new value before
    /// the two are compared (as encoded bytes, so dates match to the millisecond they're stored at);
    /// `stamp` dates the value when it is written. Returns whether it wrote.
    @discardableResult
    public func writeIfChanged<T>(_ value: T, to key: SharedKey<T>, by app: AppID, now: Date = Date(),
                                  carryOver: (inout T, T) -> Void, stamp: (inout T, Date) -> Void) throws -> Bool {
        var value = value
        // Only against a file at the key's own schema version: an older one is rewritten, so it's
        // upgraded on disk too.
        if let url = try? fileURL(key.path), let data = coordinatedRead(url),
           EnvelopeHeader.read(data)?.schemaVersion == key.schemaVersion,
           let previous = try? key.decodeEnvelope(data)?.payload {
            var unchanged = value
            carryOver(&unchanged, previous)
            let encoder = SystemJSON.encoder()
            if try encoder.encode(unchanged) == encoder.encode(previous) { return false }
        }
        stamp(&value, now)
        try write(value, to: key, by: app)
        return true
    }

    /// `writeIfChanged` for a payload with one "updated" date: it's ignored in the comparison and set
    /// to `now` when the value is written.
    @discardableResult
    public func writeIfChanged<T>(_ value: T, to key: SharedKey<T>, by app: AppID, stamp: WritableKeyPath<T, Date>,
                                  now: Date = Date()) throws -> Bool {
        try writeIfChanged(value, to: key, by: app, now: now,
                           carryOver: { $0[keyPath: stamp] = $1[keyPath: stamp] },
                           stamp: { $0[keyPath: stamp] = $1 })
    }

    /// Deletes the file at `key`, if there is one, and posts `changeNotification`.
    public func remove<T>(_ key: SharedKey<T>) throws {
        let url = try fileURL(key.path)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try coordinatedWrite(url, options: .forDeleting) { url in
            try FileManager.default.removeItem(at: url)
        }
        Self.postChange()
    }

    // MARK: Backup

    /// Every file in the container, by relative path ("core/profile.json"), for backups.
    public func allFiles() -> [String: Data] {
        let root = directory.path(percentEncoded: false)
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [:] }
        var files: [String: Data] = [:]
        while let path = enumerator.nextObject() as? String {
            if path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            let url = directory.appending(path: path, directoryHint: .notDirectory)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
                  !isDirectory.boolValue, let data = coordinatedRead(url) else { continue }
            files[path] = data
        }
        return files
    }

    /// Restores files from a backup, merging: a file whose copy on disk is newer (a later
    /// `writtenAt`, or a newer schema version) is left alone; everything else is written. Throws,
    /// writing nothing, if any path is empty, absolute or climbs out of the container.
    public func restore(_ files: [String: Data]) throws {
        try merge(files)
    }

    /// `restore`, returning how many files it wrote.
    @discardableResult
    func merge(_ files: [String: Data]) throws -> Int {
        let targets = try files.keys.sorted().map { path in (path: path, url: try fileURL(path), data: files[path] ?? Data()) }
        var written = 0
        // Announced even when a later file fails, so the files already written aren't missed.
        defer { if written > 0 { Self.postChange() } }
        for target in targets {
            try FileManager.default.createDirectory(at: target.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try coordinatedWrite(target.url, options: .forReplacing) { url in
                if let existing = try? Data(contentsOf: url) {
                    if existing == target.data { return }
                    if let onDisk = EnvelopeHeader.read(existing), let incoming = EnvelopeHeader.read(target.data),
                       onDisk.schemaVersion > incoming.schemaVersion || onDisk.writtenAt > incoming.writtenAt {
                        return
                    }
                }
                try target.data.write(to: url, options: .atomic)
                written += 1
            }
        }
        return written
    }

    /// Checks paths before an import touches anything.
    func validate(paths: some Sequence<String>) throws {
        for path in paths { _ = try fileURL(path) }
    }

    // MARK: Change notifications

    /// Calls back (on the main actor) when any app, this one included, writes to the container. Keep
    /// the returned token alive; releasing it stops the callbacks.
    public static func observeChanges(_ handler: @escaping @MainActor @Sendable () -> Void) -> AnyObject {
        DarwinObservation(name: changeNotification, handler: handler)
    }

    static func postChange() {
        notify_post(changeNotification)
    }

    // MARK: Files

    func fileURL(_ path: String) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw SystemStoreError.invalidPath(path)
        }
        return directory.appending(path: path, directoryHint: .notDirectory)
    }

    private func coordinatedRead(_ url: URL) -> Data? {
        var data: Data?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            data = try? Data(contentsOf: url)
        }
        return data
    }

    private func coordinatedWrite(_ url: URL, options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> Void) throws {
        var failure: (any Error)?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options, error: &coordinationError) { url in
            do { try body(url) } catch { failure = error }
        }
        if let failure { throw failure }
        if let coordinationError { throw coordinationError }
    }
}

/// A shared file's wrapper: which schema the payload is in, who wrote it and when.
public struct SharedEnvelope<T: Codable & Sendable>: Codable, Sendable {
    public var schemaVersion: Int
    public var writtenBy: AppID
    public var writtenAt: Date
    public var payload: T

    public init(schemaVersion: Int, writtenBy: AppID, writtenAt: Date, payload: T) {
        self.schemaVersion = schemaVersion
        self.writtenBy = writtenBy
        self.writtenAt = writtenAt
        self.payload = payload
    }
}

/// The envelope fields every shared file has, whatever its payload.
struct EnvelopeHeader: Decodable {
    var schemaVersion: Int
    var writtenAt: Date

    static func read(_ data: Data) -> EnvelopeHeader? {
        try? SystemJSON.decoder().decode(EnvelopeHeader.self, from: data)
    }
}

/// A file in the shared container: where it lives, its payload type and schema version, and how to
/// upgrade an older file.
public struct SharedKey<T: Codable & Sendable>: Sendable {
    public let path: String
    public let schemaVersion: Int
    let migrate: (@Sendable (inout [String: Any], Int) throws -> Void)?

    /// `migrate` upgrades an older file by one version (from the `Int` to the `Int + 1`). It receives
    /// the whole envelope's JSON object, so it works for any payload shape (objects and arrays): the
    /// payload is under "payload", dates are milliseconds since 1970. Called once per step, oldest
    /// first; the envelope's "schemaVersion" is updated for you. Without it, an older file is decoded
    /// as is.
    public init(path: String, schemaVersion: Int, migrate: (@Sendable (inout [String: Any], Int) throws -> Void)? = nil) {
        self.path = path
        self.schemaVersion = schemaVersion
        self.migrate = migrate
    }

    /// Decodes an envelope, migrating it step by step when older. Nil when it's newer than this key.
    func decodeEnvelope(_ data: Data) throws -> SharedEnvelope<T>? {
        let decoder = SystemJSON.decoder()
        let header = try decoder.decode(EnvelopeHeader.self, from: data)
        if header.schemaVersion > schemaVersion {
            storeLog.notice("\(path, privacy: .public) is at schema \(header.schemaVersion); this app knows \(schemaVersion)")
            return nil
        }
        if header.schemaVersion == schemaVersion || migrate == nil {
            var envelope = try decoder.decode(SharedEnvelope<T>.self, from: data)
            envelope.schemaVersion = schemaVersion
            return envelope
        }
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SystemStoreError.payloadNotAnObject(kind: path)
        }
        for version in header.schemaVersion..<schemaVersion {
            try migrate?(&json, version)
            json["schemaVersion"] = version + 1
        }
        return try decoder.decode(SharedEnvelope<T>.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

public extension SharedKey where T == SharedProfile {
    /// Setup answers, asked once and shared by every app.
    static var profile: SharedKey<SharedProfile> { SharedKey(path: "core/profile.json", schemaVersion: SharedProfile.schemaVersion) }
}

public extension SharedKey where T == [LifeModePeriod] {
    /// Tombstones included (schema 2), so a delete in one app reaches the others; version 1 files decode as is.
    static var lifeModes: SharedKey<[LifeModePeriod]> { SharedKey(path: "core/life-modes.json", schemaVersion: LifeModePeriod.schemaVersion) }
}

public extension SharedKey where T == SystemCalendar {
    static var calendar: SharedKey<SystemCalendar> { SharedKey(path: "core/calendar.json", schemaVersion: 1) }
}

public extension SharedKey where T == [Recommendation] {
    /// Written by the hub, read by the apps when they plan.
    static var recommendations: SharedKey<[Recommendation]> { SharedKey(path: "hub/recommendations.json", schemaVersion: 1) }
}

public extension SharedKey where T == [Quest] {
    static var hubQuests: SharedKey<[Quest]> { SharedKey(path: "hub/quests.json", schemaVersion: 1) }
}

public extension SharedKey where T == NutritionSummary {
    /// Published by Macro Track.
    static var nutrition: SharedKey<NutritionSummary> {
        SharedKey(path: "apps/\(AppID.macroTrack.rawValue)/nutrition.json", schemaVersion: NutritionSummary.schemaVersion)
    }
}

public extension SharedKey where T == AppSummary {
    /// Each app's published summary, for the others and the hub.
    static func summary(_ app: AppID) -> SharedKey<AppSummary> {
        SharedKey(path: "apps/\(app.rawValue)/summary.json", schemaVersion: AppSummary.schemaVersion)
    }
}

/// A libnotify registration, cancelled when released.
final class DarwinObservation {
    private var token: Int32 = 0
    private var registered = false

    init(name: String, handler: @escaping @MainActor @Sendable () -> Void) {
        let status = notify_register_dispatch(name, &token, DispatchQueue.main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        registered = status == UInt32(NOTIFY_STATUS_OK)
        if !registered { storeLog.error("Couldn't observe \(name, privacy: .public): notify status \(status)") }
    }

    deinit {
        if registered { notify_cancel(token) }
    }
}
