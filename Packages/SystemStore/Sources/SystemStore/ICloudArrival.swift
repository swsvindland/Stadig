import CloudKit
import Foundation
import Observation

/// What a person's iCloud holds for an app, asked once on a launch that finds the app not set up.
public enum ICloudContents: Sendable, Equatable {
    /// Records from another device (or an earlier install) are there.
    case records
    /// Nothing: the app's zone is missing or empty.
    case nothing
    /// No usable iCloud account on this device.
    case noAccount
    /// iCloud couldn't be asked (offline, an error).
    case unknown
}

/// On a launch that finds the app not set up: whether to wait for the person's data from iCloud
/// rather than show onboarding. A second device, or a reinstall, would otherwise open on onboarding
/// while its first import runs (seconds, or minutes for years of records), and a setup finished
/// there is newer than the one on its way down, so it would replace it.
///
/// It asks iCloud once whether the app has any records there. None, no account, or no answer within
/// `lookLimit`: onboarding at once, as for anyone new. Some: wait until this launch's first import
/// has ended (the data arriving takes the app out of onboarding by itself, before the wait ends) or
/// the person chooses to set up as new.
@MainActor @Observable
public final class ICloudArrival {
    public enum Phase: Sendable, Equatable {
        /// Asking iCloud whether there's anything.
        case looking
        /// There is: waiting for it to come down.
        case arriving
        /// Nothing to wait for, or the person chose not to.
        case settled
    }

    /// How long to wait for iCloud to say whether there's anything before treating it as nothing.
    public static let lookLimit: Duration = .seconds(10)

    public private(set) var phase: Phase = .looking
    @ObservationIgnored private let store: RecordStore
    @ObservationIgnored private(set) var lookTask: Task<Void, Never>?
    @ObservationIgnored private(set) var limitTask: Task<Void, Never>?

    /// For a launch that finds the app not set up: asks the store's CloudKit container. Nil when
    /// there's nothing to ask, because the store doesn't sync with iCloud (it couldn't open there,
    /// or nothing is kept: tests, UI tests, `-inMemoryStore`).
    public static func start(for store: RecordStore) -> ICloudArrival? {
        guard store.syncState.place == .iCloud, let container = store.cloudKitContainer else { return nil }
        return ICloudArrival(store: store) { await contents(ofContainer: container) }
    }

    /// Asks `look` rather than iCloud: tests, and the DEBUG launch argument that shows the wait.
    /// `store` is the one the data comes down into.
    public init(store: RecordStore, lookLimit: Duration = ICloudArrival.lookLimit, look: @escaping @Sendable () async -> ICloudContents) {
        self.store = store
        lookTask = Task { [weak self] in
            let contents = await look()
            self?.found(contents)
        }
        limitTask = Task { [weak self] in
            try? await Task.sleep(for: lookLimit)
            guard !Task.isCancelled else { return }
            storeLog.notice("iCloud didn't say within \(String(describing: lookLimit), privacy: .public) whether there's data; onboarding")
            self?.found(.unknown)
        }
    }

    /// Whether to keep the person on the wait rather than onboarding.
    public var isWaiting: Bool {
        switch phase {
        case .looking: true
        case .arriving: !store.syncState.firstImportSettled
        case .settled: false
        }
    }

    /// What's holding the data up, while there's something: setting up or importing failing.
    public var problem: String? { phase == .arriving ? store.syncState.problem : nil }

    /// Onboarding now, whatever iCloud holds.
    public func setUpAsNew() {
        settle()
    }

    private func found(_ contents: ICloudContents) {
        guard phase == .looking else { return }
        if contents == .records {
            limitTask?.cancel()
            phase = .arriving
            storeLog.notice("iCloud has this app's data; waiting for it to arrive")
        } else {
            settle()
        }
    }

    private func settle() {
        lookTask?.cancel()
        limitTask?.cancel()
        phase = .settled
    }

    /// The zone SwiftData's CloudKit mirroring keeps every record in.
    nonisolated static let zoneName = "com.apple.coredata.cloudkit.zone"

    /// Whether the person's private database in `identifier` has any of the app's records: the
    /// account, then one record (its id only) from the zone. Two small requests.
    @concurrent nonisolated static func contents(ofContainer identifier: String) async -> ICloudContents {
        let container = CKContainer(identifier: identifier)
        do {
            guard try await container.accountStatus() == .available else { return .noAccount }
            let zone = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
            let changes = try await container.privateCloudDatabase.recordZoneChanges(inZoneWith: zone, since: nil, desiredKeys: [], resultsLimit: 1)
            return changes.modificationResultsByID.isEmpty ? .nothing : .records
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return .nothing
        } catch {
            storeLog.error("Couldn't ask iCloud for \(identifier, privacy: .public)'s data: \(String(describing: error), privacy: .public)")
            return .unknown
        }
    }
}
