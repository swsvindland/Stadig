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
        let refused = SyncProblem.refused
        state.apply(SyncEvent(kind: .export, ended: t0, succeeded: false, problem: refused, refused: true))
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

        // An event's error as Core Data keeps it: the domain and code, nothing else. A partial
        // failure's own message ("The operation couldn't be completed. (CKErrorDomain error 2.)")
        // is what Settings showed on an iPhone whose exports a Production schema turned down.
        let partial = NSError(domain: CKErrorDomain, code: CKError.Code.partialFailure.rawValue)
        #expect(SyncProblem.reason(for: partial) == SyncProblem.refused)

        // What has no words of its own keeps its number, to look up.
        #expect(SyncProblem.reason(for: NSError(domain: CKErrorDomain, code: CKError.Code.invalidArguments.rawValue)) == "iCloud error 12")
        #expect(SyncProblem.reason(for: NSError(domain: "elsewhere", code: 1)) == "Sync error 1 (elsewhere)")
    }

    @Test func aRefusalKeepsWhatICloudSaidWhileExportsAreTurnedDown() {
        let refused = SyncEvent(kind: .export, ended: t0, succeeded: false, problem: SyncProblem.refused, refused: true)
        var state = SyncState(place: .iCloud)
        state.apply(refused)
        #expect(state.problem == SyncProblem.refused, "the event alone says no more")

        let schema = "iCloud's schema has no CD_RecordRow yet, so changes stay on this device"
        state.explainRefusals(schema)
        #expect(state.problem == schema)
        state.apply(refused)
        #expect(state.problem == schema, "the next refused export is the same refusal")

        // A different failure says itself, and a refusal after it is still explained.
        state.apply(SyncEvent(kind: .export, ended: t0 + 1, succeeded: false, problem: "No connection to iCloud"))
        #expect(state.problem == "No connection to iCloud")
        state.apply(refused)
        #expect(state.problem == schema)

        // Once an export works the reason is gone with the failure; a later refusal is asked about afresh.
        state.apply(SyncEvent(kind: .export, ended: t0 + 2, succeeded: true))
        #expect(state.problem == nil)
        state.apply(refused)
        #expect(state.problem == SyncProblem.refused)

        // A reason only stands in for a refused export, not for another kind's failure.
        var importing = SyncState(place: .iCloud)
        importing.apply(SyncEvent(kind: .import, ended: t0, succeeded: false, problem: "No connection to iCloud"))
        importing.explainRefusals(schema)
        #expect(importing.problem == "No connection to iCloud")
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

    @Test func aRefusedExportAsksICloudWhyOnce() async throws {
        let store = RecordStore(name: "refused-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: false, directory: temporaryDirectory())
        let identifier = try #require(store.storeFileURL.flatMap(SyncEvent.storeIdentifier(at:)))
        #expect(store.askWhyRefused == nil, "off iCloud there's no one to ask")
        let asked = Counter()
        let schema = "iCloud's schema has no CD_RecordRow yet, so changes stay on this device"
        store.askWhyRefused = {
            await MainActor.run { asked.value += 1 }
            return schema
        }

        // Another kind's failure, or an export failing some other way, isn't a refusal to ask about.
        store.received(SyncEvent(kind: .export, ended: t0, succeeded: false, problem: "No connection to iCloud"), fromStore: identifier)
        #expect(store.refusalQuestion == nil)

        let refused = SyncEvent(kind: .export, ended: t0 + 1, succeeded: false, problem: SyncProblem.refused, refused: true)
        store.received(refused, fromStore: identifier)
        await store.refusalQuestion?.value
        #expect(store.syncState.problem == schema)
        store.received(refused, fromStore: identifier)
        await store.refusalQuestion?.value
        #expect(asked.value == 1, "once a launch: every retry is turned down the same way")
        #expect(store.syncState.problem == schema)
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
