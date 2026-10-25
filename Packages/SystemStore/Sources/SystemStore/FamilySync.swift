import CryptoKit
import Foundation
import OSLog

/// Carries the shared container between a person's devices. The App Group only reaches the apps on
/// one device, so each app also mirrors every file in it into the family's own CloudKit database
/// (`cloudKitContainer`, which all of them are entitled to) and writes the newer copies other devices
/// put there back into the App Group. Then Stadig Mind on the Mac reads the training calendar Stadig
/// Lift wrote on the iPhone, and Stadig Macro on the iPad the measurements, as if they shared a device.
///
/// Newest wins, by the envelope's `writtenAt`, in both directions, and a file on disk at a newer
/// schema than the incoming copy is never replaced (`SharedContainer.merge`). Any app may upload any
/// file: the same file always maps to the same record, so two apps on a device uploading it agree.
/// Deleting a shared file isn't carried: no shared key deletes in normal use, and the files that
/// need deletions (life modes) keep tombstones inside.
@MainActor
public final class FamilySync {
    /// The CloudKit container every app in the family lists beside its own.
    public static let cloudKitContainer = "iCloud.dev.svindland.stadig"
    /// A burst of writes (an app publishing its summary and calendar together) goes up as one save.
    static let pushDelay: Duration = .milliseconds(500)

    let store: RecordStore
    let shared: SharedContainer
    private var sharedObserver: AnyObject?
    private var storeObserver: AnyObject?
    /// Holds `self` weakly, so it ends with this object.
    private var pendingPush: Task<Void, Never>?

    /// The family's database on its CloudKit container, mirroring `shared`. Starts syncing at once:
    /// what's in the database comes down, then what's on disk goes up.
    public convenience init(shared: SharedContainer) {
        self.init(shared: shared, store: RecordStore(name: "Family", cloudKitContainer: Self.cloudKitContainer))
    }

    init(shared: SharedContainer, store: RecordStore) {
        self.shared = shared
        self.store = store
        sync()
        // Any app's write on this device, this app's own included.
        sharedObserver = SharedContainer.observeChanges { [weak self] in self?.schedulePush() }
        // Another device's files, as CloudKit imports them.
        storeObserver = store.observeChanges { [weak self] in self?.pull() }
    }

    /// Where the family's files live: "iCloud", "This device only" or "Memory only".
    public var syncStatus: String { store.syncStatus }

    /// What CloudKit last reported doing for the family's files.
    public var syncState: SyncState { store.syncState }

    /// Both directions now: newer copies from other devices come down, then newer files here go up.
    public func sync() {
        pull()
        push()
    }

    private func schedulePush() {
        pendingPush?.cancel()
        pendingPush = Task { [weak self] in
            try? await Task.sleep(for: Self.pushDelay)
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    /// Saves every file on disk that's newer than the database's copy of it (or that it lacks).
    /// Returns how many went up.
    @discardableResult
    func push() -> Int {
        pendingPush = nil
        let uploaded = Dictionary(store.all(SharedFileRecord.self).map { ($0.path, $0) }) { first, second in
            first.updatedAt >= second.updatedAt ? first : second
        }
        var newer: [SharedFileRecord] = []
        for (path, contents) in shared.allFiles() {
            // Only envelopes: a stray file someone dropped in the folder isn't the family's to share.
            guard let header = EnvelopeHeader.read(contents) else { continue }
            let written = header.writtenAt.roundedToMilliseconds
            if let copy = uploaded[path], copy.updatedAt.wholeMilliseconds >= written.wholeMilliseconds { continue }
            newer.append(SharedFileRecord(path: path, contents: contents, updatedAt: written))
        }
        store.save(newer)
        if !newer.isEmpty {
            storeLog.info("Family: uploaded \(newer.count) shared files")
        }
        return newer.count
    }

    /// Writes every copy in the database that's newer than the file on disk. Returns how many it wrote.
    @discardableResult
    func pull() -> Int {
        var files: [String: Data] = [:]
        for record in store.all(SharedFileRecord.self) {
            // A path that would climb out of the container (or is otherwise not a shared file's) is
            // skipped on its own, so it can't hold up the others.
            do {
                try shared.validate(paths: [record.path])
            } catch {
                storeLog.error("Family: skipped a shared file at an invalid path: \(record.path, privacy: .public)")
                continue
            }
            files[record.path] = record.contents
        }
        guard !files.isEmpty else { return 0 }
        do {
            let written = try shared.merge(files)
            if written > 0 { storeLog.info("Family: wrote \(written) shared files from other devices") }
            return written
        } catch {
            storeLog.error("Family: couldn't write the shared files from other devices: \(String(describing: error), privacy: .public)")
            return 0
        }
    }
}

/// One shared file as the family's database holds it: the whole envelope, as written.
struct SharedFileRecord: StoredRecord, Equatable {
    static let kind = "shared-file"
    static let schemaVersion = 1

    var id: UUID
    var path: String
    var contents: Data
    /// The envelope's `writtenAt`, so the database's newest-wins agrees with the files'.
    var updatedAt: Date

    init(path: String, contents: Data, updatedAt: Date) {
        id = Self.id(for: path)
        self.path = path
        self.contents = contents
        self.updatedAt = updatedAt
    }

    /// The same path always gets the same record, so every app and device writes over one row.
    static func id(for path: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data("shared-file:\(path)".utf8)))
        var bytes = (
            digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7], digest[8], digest[9],
            digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
        )
        // A version 5 (name-based) UUID, RFC 4122 variant.
        bytes.6 = (bytes.6 & 0x0F) | 0x50
        bytes.8 = (bytes.8 & 0x3F) | 0x80
        return UUID(uuid: bytes)
    }
}
