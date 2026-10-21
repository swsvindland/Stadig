import CloudKit
import Foundation
import Testing

@testable import SystemStore

struct SyncStateTests {
    @Test func eventsWalkFromWaitingToUpToDate() {
        var state = SyncState(place: .iCloud)
        #expect(state.summary == "Waiting for iCloud")
        #expect(!state.firstImportSettled)

        let setup = UUID()
        state.apply(SyncEvent(id: setup, kind: .setup))
        #expect(state.isSyncing)
        #expect(state.summary == "Syncing…")
        state.apply(SyncEvent(id: setup, kind: .setup, ended: t0, succeeded: true))
        #expect(!state.isSyncing)
        #expect(state.lastSynced == nil, "setting up isn't syncing anything")
        #expect(!state.firstImportSettled)

        let importing = UUID()
        state.apply(SyncEvent(id: importing, kind: .import))
        state.apply(SyncEvent(id: importing, kind: .import, ended: t0 + 5, succeeded: true))
        #expect(state.firstImportSettled)
        #expect(state.importsEnded == 1)
        #expect(state.lastSynced == t0 + 5)
        #expect(state.summary == "Up to date")
        #expect(state.problem == nil)
    }

    @Test func aFailureStaysUntilItsOwnKindWorks() {
        var state = SyncState(place: .iCloud)
        let refused = "iCloud said: Cannot create new type CD_RecordRow in production schema"
        state.apply(SyncEvent(kind: .export, ended: t0, succeeded: false, problem: refused))
        #expect(state.problem == refused)
        #expect(state.summary == "Not syncing")

        // Changes coming down don't mean this device's are going up.
        state.apply(SyncEvent(kind: .import, ended: t0 + 10, succeeded: true))
        #expect(state.problem == refused)
        #expect(state.lastSynced == t0 + 10)

        state.apply(SyncEvent(kind: .export, ended: t0 + 20, succeeded: true))
        #expect(state.problem == nil)
        #expect(state.summary == "Up to date")
        #expect(state.lastSynced == t0 + 20)
    }

    @Test func aFailedSetupSettlesTheFirstImportAndComesFirst() {
        var state = SyncState(place: .iCloud)
        state.apply(SyncEvent(kind: .import, ended: t0, succeeded: false, problem: "No connection to iCloud"))
        #expect(state.firstImportSettled, "an import that failed has still ended")
        state.apply(SyncEvent(kind: .setup, ended: t0 + 1, succeeded: false, problem: "Not signed in to iCloud"))
        #expect(state.problem == "Not signed in to iCloud", "nothing else runs without setting up")

        var fresh = SyncState(place: .iCloud)
        fresh.apply(SyncEvent(kind: .setup, ended: t0, succeeded: false, problem: "Not signed in to iCloud"))
        #expect(fresh.firstImportSettled, "no import comes after a failed setup")
    }

    @Test func storesOffICloudSayWhereTheDataIs() {
        #expect(SyncState(place: .memory).summary == "Memory only")
        #expect(SyncState(place: .thisDevice).summary == "This device only")
        #expect(SyncState(place: .unavailable).summary == "Unavailable")
    }

    @Test func reasonsAreInWordsAPersonCanActOn() {
        #expect(SyncProblem.reason(for: CKError(.notAuthenticated)) == "Not signed in to iCloud")
        #expect(SyncProblem.reason(for: CKError(.networkUnavailable)) == "No connection to iCloud")
        #expect(SyncProblem.reason(for: CKError(.quotaExceeded)) == "iCloud storage is full")
        #expect(SyncProblem.reason(for: NSError(domain: NSCocoaErrorDomain, code: SyncProblem.noAccountCode)) == "Not signed in to iCloud")

        // A batch that partly failed: the item's own error says why.
        let item = CKError(.quotaExceeded)
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "row"): item]])
        #expect(SyncProblem.reason(for: partial) == "iCloud storage is full")
        let batch = CKError(
            .partialFailure,
            userInfo: [
                CKPartialErrorsByItemIDKey: [
                    CKRecord.ID(recordName: "a"): CKError(.batchRequestFailed), CKRecord.ID(recordName: "b"): item,
                    CKRecord.ID(recordName: "c"): CKError(.batchRequestFailed),
                ]
            ])
        #expect(SyncProblem.reason(for: batch) == "iCloud storage is full", "not one of the items that only failed with it")

        // What has no better words keeps the server's.
        let schema = CKError(.invalidArguments, userInfo: [NSLocalizedDescriptionKey: "Cannot create new type CD_RecordRow in production schema"])
        #expect(SyncProblem.reason(for: schema) == "iCloud said: Cannot create new type CD_RecordRow in production schema")
        let other = NSError(domain: "elsewhere", code: 1, userInfo: [NSLocalizedDescriptionKey: "The disk is full"])
        #expect(SyncProblem.reason(for: other) == "The disk is full")
    }
}

@MainActor
struct RecordStoreSyncTests {
    @Test func aFileStoreHasAnIdentifierForCloudKitsEvents() throws {
        let store = RecordStore(name: "id-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: false, directory: temporaryDirectory())
        let url = try #require(store.storeFileURL)
        let identifier = try #require(SyncEvent.storeIdentifier(at: url))
        #expect(!identifier.isEmpty)
        #expect(SyncEvent.storeIdentifier(at: url) == identifier, "the same every time")
    }

    @Test func anotherStoresEventsAreIgnored() throws {
        let store = RecordStore(name: "other-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: false, directory: temporaryDirectory())
        store.received(SyncEvent(kind: .export, ended: t0, succeeded: false, problem: "iCloud storage is full"), fromStore: UUID().uuidString)
        #expect(store.syncState.problem == nil)

        let identifier = try #require(store.storeFileURL.flatMap(SyncEvent.storeIdentifier(at:)))
        store.received(SyncEvent(kind: .export, ended: t0, succeeded: false, problem: "iCloud storage is full"), fromStore: identifier)
        #expect(store.syncState.problem == "iCloud storage is full")
    }

    @Test func theEndOfAnImportReadsWhatItBroughtAtOnce() throws {
        let directory = temporaryDirectory()
        let name = "import-\(UUID().uuidString)"
        let store = RecordStore(name: name, cloudKitContainer: nil, inMemory: false, directory: directory)
        let identifier = try #require(store.storeFileURL.flatMap(SyncEvent.storeIdentifier(at:)))
        let calls = Counter()
        let token = store.observeChanges { calls.value += 1 }
        #expect(store.all(Lift.self).isEmpty)

        // CloudKit's import writes the rows from its own context, as another instance does here.
        let lift = Lift(name: "Bench", updatedAt: t0)
        RecordStore(name: name, cloudKitContainer: nil, inMemory: false, directory: directory).save(lift)
        store.received(SyncEvent(kind: .import, ended: t0, succeeded: true), fromStore: identifier)

        // No waiting for the remote-change notification: the observers have run and the data is read.
        #expect(calls.value == 1)
        #expect(store.all(Lift.self) == [lift])
        #expect(store.syncState.firstImportSettled)
        withExtendedLifetime(token) {}
    }
}

@MainActor
struct ICloudArrivalTests {
    /// A store on disk, so its events can be told apart, and its identifier in them.
    func fileStore() throws -> (RecordStore, String) {
        let store = RecordStore(name: "arrival-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: false, directory: temporaryDirectory())
        return (store, try #require(store.storeFileURL.flatMap(SyncEvent.storeIdentifier(at:))))
    }

    @Test func nothingInICloudGoesStraightToOnboarding() async throws {
        for contents in [ICloudContents.nothing, .noAccount, .unknown] {
            let (store, _) = try fileStore()
            let arrival = ICloudArrival(store: store, lookLimit: .seconds(3600)) { contents }
            #expect(arrival.isWaiting, "looking, until iCloud answers")
            await arrival.lookTask?.value
            #expect(arrival.phase == .settled, "\(contents)")
            #expect(!arrival.isWaiting)
        }
    }

    @Test func recordsInICloudWaitForTheFirstImport() async throws {
        let (store, identifier) = try fileStore()
        let arrival = ICloudArrival(store: store, lookLimit: .seconds(3600)) { .records }
        await arrival.lookTask?.value
        #expect(arrival.phase == .arriving)
        #expect(arrival.isWaiting)

        let importing = UUID()
        store.received(SyncEvent(id: importing, kind: .import), fromStore: identifier)
        #expect(arrival.isWaiting, "an import under way hasn't brought anything yet")
        store.received(SyncEvent(id: importing, kind: .import, ended: t0, succeeded: true), fromStore: identifier)
        #expect(!arrival.isWaiting)
    }

    @Test func aSetupThatFailsEndsTheWaitAndSaysWhy() async throws {
        let (store, identifier) = try fileStore()
        let arrival = ICloudArrival(store: store, lookLimit: .seconds(3600)) { .records }
        await arrival.lookTask?.value
        #expect(arrival.problem == nil)
        store.received(SyncEvent(kind: .setup, ended: t0, succeeded: false, problem: "iCloud storage is full"), fromStore: identifier)
        #expect(!arrival.isWaiting)
        #expect(arrival.problem == "iCloud storage is full")
    }

    @Test func anImportThatEndedFirstLeavesNothingToWaitFor() async throws {
        let (store, identifier) = try fileStore()
        store.received(SyncEvent(kind: .import, ended: t0, succeeded: true), fromStore: identifier)
        let arrival = ICloudArrival(store: store, lookLimit: .seconds(3600)) { .records }
        await arrival.lookTask?.value
        #expect(arrival.phase == .arriving)
        #expect(!arrival.isWaiting)
    }

    @Test func noAnswerInTimeCountsAsNothing() async throws {
        let (store, _) = try fileStore()
        let arrival = ICloudArrival(store: store, lookLimit: .milliseconds(10)) {
            try? await Task.sleep(for: .seconds(3600))
            return .records
        }
        await arrival.limitTask?.value
        #expect(arrival.phase == .settled)
        // The answer that comes after giving up changes nothing.
        await arrival.lookTask?.value
        #expect(arrival.phase == .settled)
    }

    @Test func settingUpAsNewStopsWaiting() async throws {
        let (store, _) = try fileStore()
        let arrival = ICloudArrival(store: store, lookLimit: .seconds(3600)) { .records }
        await arrival.lookTask?.value
        #expect(arrival.isWaiting)
        arrival.setUpAsNew()
        #expect(arrival.phase == .settled)
        #expect(!arrival.isWaiting)
    }

    @Test func aStoreOffICloudHasNothingToLookFor() throws {
        #expect(ICloudArrival.start(for: memoryStore()) == nil)
        let (store, _) = try fileStore()
        #expect(ICloudArrival.start(for: store) == nil)
    }
}
