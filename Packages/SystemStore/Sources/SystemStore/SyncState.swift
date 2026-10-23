import CloudKit
import CoreData
import Foundation

/// What iCloud is doing for one store, as CloudKit last reported it this launch: setting up,
/// bringing other devices' changes down, sending this one's up, or failing and why. A store that
/// opened with iCloud can still be syncing nothing (no account, a schema the server refuses), which
/// `RecordStore.syncStatus` alone can't tell.
public struct SyncState: Sendable, Equatable {
    public enum Place: Sendable, Equatable {
        case iCloud, thisDevice, memory, unavailable
    }

    public let place: Place
    /// When the last import or export that worked ended.
    public private(set) var lastSynced: Date?
    /// Imports that ended this launch, whether they worked or not.
    public private(set) var importsEnded = 0
    /// The steps under way, by the event's id: CloudKit reports each one starting and ending.
    private var running: [UUID: SyncEvent.Kind] = [:]
    /// Each kind's latest failure, until that kind next works.
    private var failures: [SyncEvent.Kind: String] = [:]
    /// Whether the latest export failed because iCloud turned records down.
    private var exportRefused = false
    /// Why it does, from `explainRefusals`, until an export works.
    private var refusalReason: String?

    public init(place: Place) {
        self.place = place
    }

    /// Why the store isn't syncing, in words: setting up first (nothing else runs without it), then
    /// sending, then bringing changes down. Nil while everything that has run has worked.
    public var problem: String? { failures[.setup] ?? failures[.export] ?? failures[.import] }

    public var isSyncing: Bool { !running.isEmpty }

    /// Whether this launch's first import has ended, or never will because setting up failed.
    public var firstImportSettled: Bool { importsEnded > 0 || failures[.setup] != nil }

    /// For Settings: where the data lives, or for iCloud how syncing is going.
    public var summary: String {
        switch place {
        case .memory: RecordStore.memoryStatus
        case .thisDevice: RecordStore.localStatus
        case .unavailable: "Unavailable"
        case .iCloud:
            if problem != nil {
                "Not syncing"
            } else if isSyncing {
                "Syncing…"
            } else if lastSynced != nil {
                "Up to date"
            } else {
                "Waiting for iCloud"
            }
        }
    }

    mutating func apply(_ event: SyncEvent) {
        guard let ended = event.ended else {
            running[event.id] = event.kind
            return
        }
        running[event.id] = nil
        if event.kind == .import { importsEnded += 1 }
        let refusal = event.kind == .export && event.refused
        if event.succeeded {
            failures[event.kind] = nil
            if event.kind != .setup { lastSynced = max(lastSynced ?? ended, ended) }
        } else {
            failures[event.kind] = (refusal ? refusalReason : nil) ?? event.problem ?? "Something went wrong with iCloud"
        }
        if event.kind == .export {
            exportRefused = refusal
            // Records going up means iCloud takes them now.
            if event.succeeded { refusalReason = nil }
        }
    }

    /// Why iCloud turns this device's records down, once it's been asked (the event doesn't say):
    /// in place of the bare words for as long as exports keep being turned down.
    mutating func explainRefusals(_ reason: String) {
        refusalReason = reason
        if exportRefused { failures[.export] = reason }
    }
}

/// One step of CloudKit's work on a store, from `NSPersistentCloudKitContainer`'s event: reported
/// once as it starts (`ended` nil) and again as it ends.
struct SyncEvent: Sendable, Equatable {
    enum Kind: Sendable, Hashable {
        case setup, `import`, export
    }

    var id: UUID
    var kind: Kind
    var ended: Date?
    var succeeded: Bool
    /// Why it failed, in words.
    var problem: String?
    /// It failed because iCloud turned some records down (a partial failure). The event says no
    /// more than that, so this is the failure worth asking iCloud about.
    var refused: Bool

    init(id: UUID = UUID(), kind: Kind, ended: Date? = nil, succeeded: Bool = false, problem: String? = nil, refused: Bool = false) {
        self.id = id
        self.kind = kind
        self.ended = ended
        self.succeeded = succeeded
        self.problem = problem
        self.refused = refused
    }

    /// Nil for a kind of step this version doesn't know.
    init?(_ event: NSPersistentCloudKitContainer.Event) {
        let kind: Kind
        switch event.type {
        case .setup: kind = .setup
        case .import: kind = .import
        case .export: kind = .export
        @unknown default: return nil
        }
        let error = event.error as NSError?
        self.init(
            id: event.identifier, kind: kind, ended: event.endDate, succeeded: event.succeeded,
            problem: error.map(SyncProblem.reason(for:)),
            refused: error.map { $0.domain == CKErrorDomain && $0.code == CKError.Code.partialFailure.rawValue } ?? false)
    }

    /// Calls `handler` on the main actor with every store's CloudKit events in this process, each
    /// with the identifier of the store it's for (an app's own store and the family's both sync).
    /// Keep the returned observation alive; releasing it stops the calls.
    static func observe(_ handler: @escaping @MainActor @Sendable (SyncEvent, String) -> Void) -> NotificationObservation {
        let token = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main)
        {
            note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                let sync = SyncEvent(event)
            else { return }
            let store = event.storeIdentifier
            MainActor.assumeIsolated { handler(sync, store) }
        }
        return NotificationObservation(token)
    }

    /// The identifier CloudKit's events name a store by: its file's store UUID.
    static func storeIdentifier(at url: URL) -> String? {
        do {
            return try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)[NSStoreUUIDKey] as? String
        } catch {
            storeLog.error(
                "Couldn't read the store identifier at \(url.path(percentEncoded: false), privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }
}

enum SyncProblem {
    /// Core Data's error when CloudKit mirroring starts without an iCloud account.
    static let noAccountCode = 134400

    /// What a partial failure says: iCloud turned some of the records down, not which or why.
    static let refused = "iCloud turned down some changes"

    /// A CloudKit failure in words a person can act on, from its domain and code alone: that's all
    /// of an event's error Core Data keeps (its `ANSCKEVENT` table has columns for nothing else),
    /// so the server's message and a partial failure's errors for each record never get here.
    static func reason(for error: any Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == noAccountCode { return "Not signed in to iCloud" }
        guard let error = error as? CKError else { return "Sync error \(nsError.code) (\(nsError.domain))" }
        switch error.code {
        case .partialFailure: return refused
        case .notAuthenticated: return "Not signed in to iCloud"
        case .accountTemporarilyUnavailable: return "Your iCloud account needs attention"
        case .networkUnavailable, .networkFailure: return "No connection to iCloud"
        case .quotaExceeded: return "iCloud storage is full"
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud is busy; it will try again"
        case .userDeletedZone: return "This app's iCloud data was deleted"
        case .incompatibleVersion: return "Update the app to keep syncing"
        case .permissionFailure, .managedAccountRestricted: return "iCloud isn't allowed for this app"
        // The number is what there is to look up.
        default: return "iCloud error \(error.errorCode)"
        }
    }

    /// Why iCloud turns a store's records down, when it's the usual reason: the environment the
    /// build syncs with (Production, for TestFlight and the App Store) has no `recordType` in its
    /// schema, which Development builds create as they go but Production only gets when it's
    /// deployed. Asked with a query for the type, which the server answers with "unknown item"
    /// when it has none. Nil when the type is there, or iCloud couldn't be asked.
    @concurrent nonisolated static func missingRecordType(_ recordType: String, inContainer identifier: String) async -> String? {
        let database = CKContainer(identifier: identifier).privateCloudDatabase
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        do {
            _ = try await database.records(matching: query, inZoneWith: nil, desiredKeys: [], resultsLimit: 1)
            return nil
        } catch let error as CKError where error.code == .unknownItem {
            return "iCloud's schema has no \(recordType) yet, so changes stay on this device"
        } catch {
            storeLog.notice(
                "Couldn't ask \(identifier, privacy: .public) about \(recordType, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
