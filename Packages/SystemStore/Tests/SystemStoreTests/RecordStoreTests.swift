import Foundation
import Synchronization
import SystemCore
import Testing

@testable import SystemStore

@MainActor
struct RecordStoreTests {
    @Test func insertingNewRecordsReadsLikeSavingThem() {
        let store = memoryStore()
        store.save(Lift(name: "Bench", reps: 5, updatedAt: t0))
        _ = store.all(Lift.self)
        let revision = store.revision
        let new = [Lift(name: "Squat", reps: 3, updatedAt: t0 + 60), Lift(name: "Row", reps: 8, updatedAt: t0 + 120)]

        let stored = store.insert(new)

        #expect(stored == new)
        #expect(store.revision == revision + 1)
        #expect(store.all(Lift.self).map(\.name) == ["Row", "Squat", "Bench"])
        #expect(store.get(Lift.self, id: new[0].id) == new[0])
        #expect(store.rows(kind: Lift.kind).count == 3)
    }

    @Test func aRecordInsertedCanBeSavedAndDeletedLikeAnyOther() {
        let store = memoryStore()
        var lift = Lift(name: "Squat", reps: 3, updatedAt: t0)
        store.insert([lift])
        lift.reps = 5
        lift.updatedAt = t0 + 60
        store.save(lift)
        #expect(store.all(Lift.self) == [lift])
        #expect(store.rows(kind: Lift.kind).count == 1)
        store.delete(Lift.self, id: lift.id)
        #expect(store.all(Lift.self).isEmpty)
    }

    @Test func anInsertThatFailsToSaveStoresAndReturnsNothing() {
        let store = memoryStore()
        store.save(Lift(name: "Bench", reps: 5, updatedAt: t0))
        _ = store.all(Lift.self)
        let revision = store.revision
        store.nextSaveFailure = CocoaError(.fileWriteOutOfSpace)

        let stored = store.insert([Lift(name: "Squat", reps: 3, updatedAt: t0 + 60)])

        #expect(stored.isEmpty, "a caller mustn't show what isn't in the store")
        #expect(store.revision == revision + 1, "the kind is read again")
        #expect(store.all(Lift.self).map(\.name) == ["Bench"])
        #expect(store.rows(kind: Lift.kind).count == 1)

        // Rolled back, so the next save doesn't take the failed one with it.
        let row = Lift(name: "Row", reps: 8, updatedAt: t0 + 120)
        #expect(store.insert([row]) == [row])
        #expect(store.all(Lift.self).map(\.name) == ["Row", "Bench"])
    }

    @Test func insertingNothingChangesNothing() {
        let store = memoryStore()
        #expect(store.insert([Lift]()).isEmpty)
        #expect(store.revision == 0)
    }

    @Test func deletingSeveralIsOneChange() {
        let store = memoryStore()
        let lifts = (0..<3).map { Lift(name: "Lift \($0)", reps: 5, updatedAt: t0 + Double($0)) }
        store.save(lifts)
        _ = store.all(Lift.self)
        let revision = store.revision

        store.delete(Lift.self, ids: [lifts[0].id, lifts[2].id, lifts[2].id, UUID()])

        #expect(store.revision == revision + 1)
        #expect(store.all(Lift.self) == [lifts[1]])
        #expect(store.deletedIDs(Lift.self) == [lifts[0].id, lifts[2].id])
    }

    @Test func deletingManyReadsThemAgainInOneGo() {
        let store = memoryStore()
        let lifts = (0..<40).map { Lift(name: "Lift \($0)", reps: 5, updatedAt: t0 + Double($0)) }
        store.save(lifts)
        _ = store.all(Lift.self)

        store.delete(Lift.self, ids: lifts.dropFirst().map(\.id))

        #expect(store.all(Lift.self) == [lifts[0]])
        #expect(store.deletedIDs(Lift.self).count == 39)
    }

    @Test func deletingNothingChangesNothing() {
        let store = memoryStore()
        store.save(Lift(name: "Squat", reps: 3, updatedAt: t0))
        let revision = store.revision
        store.delete(Lift.self, ids: [])
        store.delete(Lift.self, ids: [UUID()])
        #expect(store.revision == revision)
    }

    @Test func saveGetAllRoundTrip() {
        let store = memoryStore()
        #expect(store.syncStatus == "Memory only")
        let bench = Lift(name: "Bench, paused", reps: 5, notes: "Said \"tight\"", updatedAt: t0)
        let squat = Lift(name: "Squat", reps: 3, updatedAt: t0 + 60)

        store.save(bench)
        #expect(store.revision == 1)
        store.save([squat])
        #expect(store.revision == 2)

        #expect(store.get(Lift.self, id: bench.id) == bench)
        #expect(store.get(Lift.self, id: UUID()) == nil)
        #expect(store.all(Lift.self) == [squat, bench], "newest first")

        // Saving the same version again changes nothing.
        store.save(bench)
        #expect(store.revision == 2)
        #expect(store.rows(kind: Lift.kind).count == 2)
    }

    @Test func updatedAtIsKeptToTheMillisecond() throws {
        let store = memoryStore()
        let now = Date()
        let lift = Lift(name: "Row", updatedAt: now)
        store.save(lift)
        let read = try #require(store.get(Lift.self, id: lift.id))
        #expect(read.updatedAt.wholeMilliseconds == now.wholeMilliseconds)
        #expect(abs(read.updatedAt.timeIntervalSince(now)) < 0.001)

        // The copy read back saves again without being mistaken for an older write.
        var edited = read
        edited.reps = 8
        store.save(edited)
        #expect(store.get(Lift.self, id: lift.id)?.reps == 8)
    }

    @Test func olderWriteIsIgnored() {
        let store = memoryStore()
        let id = UUID()
        store.save(Lift(id: id, name: "Bench", reps: 5, updatedAt: t0 + 10))
        let revision = store.revision

        store.save(Lift(id: id, name: "Bench", reps: 3, updatedAt: t0))
        #expect(store.get(Lift.self, id: id)?.reps == 5)
        #expect(store.revision == revision, "an ignored write isn't a change")

        store.save(Lift(id: id, name: "Bench", reps: 8, updatedAt: t0 + 20))
        #expect(store.get(Lift.self, id: id)?.reps == 8)
        #expect(store.rows(kind: Lift.kind).count == 1, "upsert, not insert")

        // In a batch too, and the newest of two copies in one batch wins.
        store.save([
            Lift(id: id, name: "Bench", reps: 1, updatedAt: t0 + 15),
            Lift(id: id, name: "Bench", reps: 10, updatedAt: t0 + 40),
            Lift(id: id, name: "Bench", reps: 9, updatedAt: t0 + 30),
        ])
        #expect(store.get(Lift.self, id: id)?.reps == 10)
        #expect(store.rows(kind: Lift.kind).count == 1)
    }

    @Test func duplicateRowsResolveToTheNewest() throws {
        let store = memoryStore()
        let id = UUID()
        // CloudKit delivered three rows for one record: two devices created it before syncing.
        for (name, offset) in [("Old", 0.0), ("New", 5.0), ("Mid", 2.0)] {
            let lift = Lift(id: id, name: name, updatedAt: t0 + offset)
            store.insertRawRow(kind: Lift.kind, uuid: id, updatedAt: lift.updatedAt, schemaVersion: Lift.schemaVersion, payload: try payload(lift))
        }
        #expect(store.rows(kind: Lift.kind).count == 3)
        #expect(store.all(Lift.self).map(\.name) == ["New"])
        #expect(store.get(Lift.self, id: id)?.name == "New")

        // A write older than the newest copy is ignored, even though it's newer than the others.
        store.save(Lift(id: id, name: "Stale", updatedAt: t0 + 3))
        #expect(store.get(Lift.self, id: id)?.name == "New")

        // A newer write goes into every copy, so they converge.
        store.save(Lift(id: id, name: "Newest", updatedAt: t0 + 10))
        let rows = store.rows(kind: Lift.kind)
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.updatedAt == t0 + 10 })
        #expect(store.all(Lift.self).map(\.name) == ["Newest"])
    }

    @Test func newestDuplicateDeletionWins() throws {
        let store = memoryStore()
        let id = UUID()
        let lift = Lift(id: id, name: "Dip", updatedAt: t0)
        store.insertRawRow(kind: Lift.kind, uuid: id, updatedAt: t0, schemaVersion: 2, payload: try payload(lift))
        store.insertRawRow(kind: Lift.kind, uuid: id, updatedAt: t0 + 1, schemaVersion: 2, payload: Data(), deleted: true)
        #expect(store.all(Lift.self).isEmpty)
        #expect(store.get(Lift.self, id: id) == nil)
    }

    @Test func softDeleteHidesTheRecord() throws {
        let store = memoryStore()
        let keep = Lift(name: "Bench", updatedAt: t0)
        let drop = Lift(name: "Dip", updatedAt: t0)
        store.save([keep, drop])

        store.delete(Lift.self, id: drop.id)
        #expect(store.get(Lift.self, id: drop.id) == nil)
        #expect(store.all(Lift.self) == [keep])

        let row = try #require(store.rows(kind: Lift.kind).first { $0.uuid == drop.id })
        #expect(row.deleted)
        #expect(row.payload.isEmpty)
        #expect(row.updatedAt > drop.updatedAt, "the deletion is newer than the last edit, so it syncs and wins")

        // The old copy can't come back, but a newer edit can.
        let revision = store.revision
        store.save(drop)
        #expect(store.get(Lift.self, id: drop.id) == nil)
        #expect(store.revision == revision)
        var restored = drop
        restored.updatedAt = row.updatedAt + 1
        store.save(restored)
        #expect(store.get(Lift.self, id: drop.id) == restored)

        // Deleting something that isn't there does nothing.
        store.delete(Lift.self, id: UUID())
        #expect(store.rows(kind: Lift.kind).count == 2)
    }

    @Test func v1RowIsMigratedOnRead() throws {
        let store = memoryStore()
        let id = UUID()
        store.insertRawRow(
            kind: Lift.kind, uuid: id, updatedAt: t0, schemaVersion: 1,
            payload: try v1Payload(id: id, title: "Squat", reps: 3, updatedAt: t0))

        let expected = Lift(id: id, name: "Squat", reps: 3, notes: "", updatedAt: t0)
        #expect(store.get(Lift.self, id: id) == expected)
        #expect(store.all(Lift.self) == [expected])
        #expect(store.rows(kind: Lift.kind).first?.schemaVersion == 1, "reading doesn't rewrite the row")

        // Saving writes it at the current version.
        var edited = expected
        edited.reps = 5
        edited.updatedAt = t0 + 1
        store.save(edited)
        let row = try #require(store.rows(kind: Lift.kind).first)
        #expect(row.schemaVersion == 2)
        #expect(store.get(Lift.self, id: id) == edited)
    }

    @Test func rowFromANewerAppVersionIsSkippedAndNotOverwritten() throws {
        let store = memoryStore()
        let id = UUID()
        let future = Data(#"{"id":"\#(id.uuidString)","name":"Clean","reps":2,"notes":"","updatedAt":1760000000000,"tempo":"31X1"}"#.utf8)
        store.insertRawRow(kind: Lift.kind, uuid: id, updatedAt: t0, schemaVersion: 3, payload: future)

        #expect(store.all(Lift.self).isEmpty)
        #expect(store.get(Lift.self, id: id) == nil)

        store.save(Lift(id: id, name: "Clean", reps: 1, updatedAt: t0 + 60))
        let row = try #require(store.rows(kind: Lift.kind).first)
        #expect(row.schemaVersion == 3)
        #expect(row.payload == future)
    }

    @Test func deletedIDsAreOnlyTheDeletions() throws {
        let store = memoryStore()
        let keep = Lift(name: "Bench", updatedAt: t0)
        let drop = Lift(name: "Dip", updatedAt: t0)
        store.save([keep, drop])
        store.delete(Lift.self, id: drop.id)
        // A newer app version's row can't be read here, but it isn't a deletion either.
        let future = UUID()
        store.insertRawRow(
            kind: Lift.kind, uuid: future, updatedAt: t0, schemaVersion: 3,
            payload: Data(#"{"id":"\#(future.uuidString)","name":"Clean","reps":2,"notes":"","updatedAt":1760000000000}"#.utf8))
        // Two rows for one record: the newer, a deletion, speaks for it.
        let twice = UUID()
        store.insertRawRow(
            kind: Lift.kind, uuid: twice, updatedAt: t0, schemaVersion: 2, payload: try payload(Lift(id: twice, name: "Row", updatedAt: t0)))
        store.insertRawRow(kind: Lift.kind, uuid: twice, updatedAt: t0 + 1, schemaVersion: 2, payload: Data(), deleted: true)

        #expect(store.deletedIDs(Lift.self) == [drop.id, twice])
        #expect(!store.deletedIDs(Lift.self).contains(future))
        #expect(!store.deletedIDs(Lift.self).contains(UUID()), "a record that was never here isn't a deletion")

        // Saved again later, it's live once more.
        var restored = drop
        restored.updatedAt = Date().addingTimeInterval(60)
        store.save(restored)
        #expect(store.deletedIDs(Lift.self) == [twice])
    }

    @Test func eraseAllRemovesEveryRow() {
        let store = memoryStore()
        store.save([Lift(name: "A", updatedAt: t0), Lift(name: "B", updatedAt: t0)])
        let revision = store.revision
        store.eraseAll()
        #expect(store.all(Lift.self).isEmpty)
        #expect(store.rows(kind: Lift.kind).isEmpty)
        #expect(store.revision == revision + 1)
    }

    @Test func backupExportEraseImportRestoresEverythingAndMergesNewestWins() throws {
        let shared = temporarySharedContainer()
        let profile = SharedProfile(goals: [], createdBy: .liftTrack, createdAt: t0, updatedAt: t0)
        try shared.write(profile, to: .profile, by: .liftTrack)

        let store = memoryStore()
        let bench = Lift(name: "Bench", updatedAt: t0)
        let row = Lift(name: "Row", updatedAt: t0)
        let dip = Lift(name: "Dip", updatedAt: t0)
        store.save([bench, row, dip])
        store.delete(Lift.self, id: dip.id)
        let squatID = UUID()
        store.insertRawRow(
            kind: Lift.kind, uuid: squatID, updatedAt: t0, schemaVersion: 1,
            payload: try v1Payload(id: squatID, title: "Squat", reps: 3, updatedAt: t0))

        let backup = try store.exportBackup(app: .liftTrack, shared: shared)
        let file = try BackupFile(data: backup)
        #expect(file.format == "system-backup")
        #expect(file.app == .liftTrack)
        #expect(file.records.count == 4, "deletions are included so they carry over")
        #expect(Set(file.shared.keys) == ["core/profile.json"])
        let text = String(decoding: backup, as: UTF8.self)
        #expect(text.contains("\"name\" : \"Bench\""), "payloads embed as readable JSON")

        store.eraseAll()
        #expect(store.all(Lift.self).isEmpty)

        let restoredShared = temporarySharedContainer()
        let summary = try store.importBackup(backup, app: .liftTrack, shared: restoredShared)
        #expect(summary == BackupSummary(records: 3, kinds: ["lift": 3], sharedFiles: 1))
        #expect(Set(store.all(Lift.self).map(\.name)) == ["Bench", "Row", "Squat"], "the v1 row restores and migrates")
        #expect(store.get(Lift.self, id: bench.id) == bench)
        #expect(store.get(Lift.self, id: dip.id) == nil)
        #expect(store.rows(kind: Lift.kind).first { $0.uuid == dip.id }?.deleted == true)
        #expect(restoredShared.read(.profile) == profile)

        // A local edit newer than the backup survives importing it again.
        var pausedBench = bench
        pausedBench.name = "Bench (paused)"
        pausedBench.updatedAt = t0 + 60
        store.save(pausedBench)
        let again = try store.importBackup(backup, app: .liftTrack, shared: nil)
        #expect(again == BackupSummary())
        #expect(store.get(Lift.self, id: bench.id) == pausedBench)

        // An older local copy is replaced by the backup's.
        let other = memoryStore()
        var oldRow = row
        oldRow.name = "Row (old)"
        oldRow.updatedAt = t0 - 60
        other.save(oldRow)
        let merged = try other.importBackup(backup, app: .liftTrack, shared: nil)
        #expect(merged.records == 3)
        #expect(other.get(Lift.self, id: row.id) == row)
    }

    @Test func importRefusesWhatIsntABackup() throws {
        let store = memoryStore()
        #expect(throws: SystemStoreError.notABackup) { try store.importBackup(Data("{}".utf8), app: .liftTrack, shared: nil) }
        #expect(throws: SystemStoreError.notABackup) { try store.importBackup(Data("not json".utf8), app: .liftTrack, shared: nil) }
        let future = Data(#"{"format":"system-backup","formatVersion":99,"app":"liftTrack","created":0,"records":[],"shared":{}}"#.utf8)
        #expect(throws: SystemStoreError.backupFromNewerVersion(formatVersion: 99)) { try store.importBackup(future, app: .liftTrack, shared: nil) }

        // A bad shared path fails the import before anything is written.
        let lift = Lift(name: "Bench", updatedAt: t0)
        let hostile = BackupFile(
            app: .liftTrack,
            records: [
                BackupRecord(
                    kind: Lift.kind, uuid: lift.id, updatedAt: t0, schemaVersion: 2,
                    payload: try payload(lift), deleted: false)
            ],
            shared: ["../outside.json": Data("{}".utf8)])
        let data = try SystemJSON.encoder().encode(hostile)
        #expect(throws: SystemStoreError.invalidPath("../outside.json")) {
            try store.importBackup(data, app: .liftTrack, shared: temporarySharedContainer())
        }
        #expect(store.all(Lift.self).isEmpty)
    }

    @Test func fileStorePersistsAcrossLaunches() throws {
        let directory = temporaryDirectory()
        let name = "persist-\(UUID().uuidString)"
        let bench = Lift(name: "Bench", updatedAt: t0)
        let dip = Lift(name: "Dip", updatedAt: t0)
        do {
            let store = RecordStore(name: name, cloudKitContainer: nil, inMemory: false, directory: directory)
            #expect(store.syncStatus == "This device only")
            store.save([bench, dip])
            store.delete(Lift.self, id: dip.id)
        }
        let reopened = RecordStore(name: name, cloudKitContainer: nil, inMemory: false, directory: directory)
        #expect(reopened.all(Lift.self) == [bench])
        #expect(reopened.rows(kind: Lift.kind).first { $0.uuid == dip.id }?.deleted == true)
    }

    /// `swift test`'s runner has no bundle identifier or iCloud entitlement; a test host on a simulator may have both.
    @Test(.enabled(if: Bundle.main.bundleIdentifier == nil, "needs a runner without a bundle identifier"))
    func cloudKitStoreThatCantOpenFallsBackWithoutCrashing() {
        let store = RecordStore(
            name: "cloud-\(UUID().uuidString)", cloudKitContainer: "iCloud.dev.svindland.systemstore.tests",
            inMemory: false, directory: temporaryDirectory())
        #expect(store.syncStatus == "This device only")
        let lift = Lift(name: "Bench", updatedAt: t0)
        store.save(lift)
        #expect(store.get(Lift.self, id: lift.id) == lift)
    }

    @Test func remoteChangeBumpsTheRevision() async throws {
        let directory = temporaryDirectory()
        let name = "remote-\(UUID().uuidString)"
        let store = RecordStore(name: name, cloudKitContainer: nil, inMemory: false, directory: directory)
        let url = try #require(store.storeFileURL)
        let calls = Counter()
        let token = store.observeChanges { calls.value += 1 }
        let before = store.revision

        // Another process (or CloudKit, importing another device's edit) writes the same file.
        let elsewhere = RecordStore(name: name, cloudKitContainer: nil, inMemory: false, directory: directory)
        let lift = Lift(name: "Bench", updatedAt: t0)
        elsewhere.save(lift)
        // A burst of notifications coalesces into one refresh; another store's are ignored.
        let remoteChange = Notification.Name("NSPersistentStoreRemoteChangeNotification")
        for _ in 0..<3 { NotificationCenter.default.post(name: remoteChange, object: nil, userInfo: ["storeURL": url]) }
        NotificationCenter.default.post(name: remoteChange, object: nil, userInfo: ["storeURL": URL(filePath: "/tmp/other.store")])
        for _ in 0..<60 where calls.value == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(1500))
        #expect(calls.value == 1)
        #expect(store.revision == before + 1)
        #expect(store.all(Lift.self) == [lift], "a fresh context reads what the other process wrote")
        withExtendedLifetime(token) {}
    }

    @Test func ownSavesDontLookRemote() async throws {
        // The remote-change notification fires for this store's own saves too.
        let store = RecordStore(name: "echo-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: false, directory: temporaryDirectory())
        let calls = Counter()
        let token = store.observeChanges { calls.value += 1 }
        store.save(Lift(name: "Bench", updatedAt: t0))
        store.delete(Lift.self, id: store.all(Lift.self)[0].id)
        let revision = store.revision
        try await Task.sleep(for: .milliseconds(1500))
        #expect(calls.value == 0)
        #expect(store.revision == revision, "the echo of a save doesn't clear the caches again")
        withExtendedLifetime(token) {}
    }

    @Test func releasingTheTokenStopsTheCalls() async throws {
        let directory = temporaryDirectory()
        let name = "token-\(UUID().uuidString)"
        let store = RecordStore(name: name, cloudKitContainer: nil, inMemory: false, directory: directory)
        let calls = Counter()
        var token: AnyObject? = store.observeChanges { calls.value += 1 }
        weak let released = token
        token = nil
        #expect(released == nil, "the store doesn't keep the token alive")

        let before = store.revision
        RecordStore(name: name, cloudKitContainer: nil, inMemory: false, directory: directory).save(Lift(name: "Row", updatedAt: t0))
        for _ in 0..<60 where store.revision == before {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.revision == before + 1)
        #expect(calls.value == 0)
    }
}

/// Counts callbacks on the main actor.
@MainActor final class Counter {
    var value = 0
}

/// A second record kind that counts its decodes, so a test can see which caches a write cleared.
/// Only `RecordStoreCacheTests.aWriteClearsOnlyItsOwnKind` uses it, so parallel tests don't share the count.
struct CountedNote: StoredRecord, Equatable {
    static let kind = "counted-note"
    static let schemaVersion = 1
    static let decodes = Mutex(0)

    var id: UUID
    var text: String
    var updatedAt: Date

    init(id: UUID = UUID(), text: String, updatedAt: Date) {
        self.id = id
        self.text = text
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case id, text, updatedAt }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        Self.decodes.withLock { $0 += 1 }
    }
}

/// `CountedNote` with a second date, for `RecordStoreCacheTests.aLocalWritePatchesItsKindInPlace` alone.
struct TimedNote: StoredRecord, Equatable {
    static let kind = "timed-note"
    static let schemaVersion = 1
    static let decodes = Mutex(0)

    var id: UUID
    var text: String
    var takenAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), text: String, takenAt: Date = t0, updatedAt: Date) {
        self.id = id
        self.text = text
        self.takenAt = takenAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case id, text, takenAt, updatedAt }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        takenAt = try container.decode(Date.self, forKey: .takenAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        Self.decodes.withLock { $0 += 1 }
    }
}

@MainActor
struct RecordStoreCacheTests {
    @Test func aLocalWritePatchesItsKindInPlace() throws {
        func decodes() -> Int { TimedNote.decodes.withLock { $0 } }
        let store = memoryStore()
        var notes = (0..<200).map { TimedNote(text: "Note \($0)", updatedAt: t0 + Double($0)) }
        notes.append(TimedNote(text: "In note 100's millisecond", updatedAt: t0 + 100))
        store.save(notes)
        #expect(store.all(TimedNote.self).count == 201)
        var decoded = decodes()

        // A new note is listed first at once, as it reads back from its row, and only it is decoded.
        let new = TimedNote(text: "New", takenAt: t0 + 0.0004, updatedAt: t0 + 500)
        store.save(new)
        var all = store.all(TimedNote.self)
        #expect(decodes() == decoded + 1)
        #expect(all.count == 202)
        #expect(all.first?.id == new.id)
        #expect(all.first?.takenAt == t0, "to the millisecond, like a fresh read")
        #expect(store.revision(of: TimedNote.self) == store.revision)

        // An edit moves to its new place, a note in another's millisecond goes by its id, a delete leaves.
        var edited = notes[3]
        edited.text = "Edited"
        edited.updatedAt = t0 + 150
        store.save([edited, TimedNote(text: "Also in note 100's millisecond", updatedAt: t0 + 100)])
        store.delete(TimedNote.self, id: notes[7].id)
        all = store.all(TimedNote.self)
        #expect(decodes() == decoded + 3, "nothing but the saved notes was decoded")
        #expect(all.count == 202)
        #expect(!all.contains { $0.id == notes[7].id })
        #expect(all.filter { $0.id == edited.id } == [edited])
        #expect(all == store.uncachedAll(TimedNote.self), "the same notes in the same order as reading the rows")
        decoded = decodes()

        // Writes the store ignores change nothing: an older copy, a second delete.
        let revision = store.revision
        store.save(notes[3])
        store.delete(TimedNote.self, id: notes[7].id)
        #expect(store.revision == revision)
        #expect(store.all(TimedNote.self) == all)
        #expect(decodes() == decoded)

        // A big batch is read again whole, and still lands in order.
        store.save(
            (0..<40).map { i in
                var note = notes[100 + i]
                note.updatedAt = t0 + 1000 + Double(i % 3)
                return note
            })
        #expect(store.all(TimedNote.self).count == 202)
        #expect(store.all(TimedNote.self) == store.uncachedAll(TimedNote.self))
    }

    @Test func aPatchedListMatchesReadingTheRows() throws {
        let store = memoryStore()
        // Two rows of one record from two devices, a row an older app version wrote, and one from a newer.
        let duplicate = UUID()
        let old = UUID()
        let future = UUID()
        for offset in [0.0, 5.0] {
            store.insertRawRow(
                kind: Lift.kind, uuid: duplicate, updatedAt: t0 + offset, schemaVersion: 2,
                payload: try payload(Lift(id: duplicate, name: "Copy", updatedAt: t0 + offset)))
        }
        store.insertRawRow(
            kind: Lift.kind, uuid: old, updatedAt: t0, schemaVersion: 1,
            payload: try v1Payload(id: old, title: "Squat", reps: 3, updatedAt: t0))
        let futurePayload = Data(#"{"id":"\#(future.uuidString)","name":"Clean","reps":2,"notes":"","updatedAt":1760000000000,"tempo":"31X1"}"#.utf8)
        store.insertRawRow(kind: Lift.kind, uuid: future, updatedAt: t0, schemaVersion: 3, payload: futurePayload)
        let bench = Lift(name: "Bench", updatedAt: t0 + 1)
        store.save(bench)
        #expect(store.all(Lift.self).count == 3, "the newer app's lift stays unreadable")

        store.save(Lift(id: duplicate, name: "Converged", updatedAt: t0 + 10))
        store.save(Lift(id: old, name: "Squat", reps: 5, updatedAt: t0 + 2))
        store.save(Lift(id: future, name: "Clean", updatedAt: t0 + 60))
        store.delete(Lift.self, id: bench.id)
        #expect(store.all(Lift.self).map(\.name) == ["Converged", "Squat"])

        // Saved again in its deletion's own millisecond, it comes back.
        let tombstone = try #require(store.rows(kind: Lift.kind).first { $0.uuid == bench.id })
        var again = bench
        again.reps = 8
        again.updatedAt = tombstone.updatedAt
        store.save(again)
        let patched = store.all(Lift.self)
        #expect(patched.map(\.name) == ["Bench", "Converged", "Squat"])
        #expect(patched.first == again)
        #expect(patched == store.uncachedAll(Lift.self))
        #expect(patched.map(\.id).compactMap { store.get(Lift.self, id: $0) } == patched)

        // A row that arrives some other way drops the cache rather than patching it.
        let synced = Lift(name: "Row", updatedAt: t0 + 3)
        store.insertRawRow(kind: Lift.kind, uuid: synced.id, updatedAt: synced.updatedAt, schemaVersion: 2, payload: try payload(synced))
        #expect(store.all(Lift.self).map(\.name) == ["Bench", "Converged", "Row", "Squat"])
    }

    @Test func aWriteClearsOnlyItsOwnKind() throws {
        let store = memoryStore()
        let notes = (0..<1000).map { CountedNote(text: "Note \($0)", updatedAt: t0 + Double($0)) }
        store.save(notes)
        let bench = Lift(name: "Bench", updatedAt: t0)
        store.save(bench)
        #expect(store.all(CountedNote.self).count == 1000)
        let decoded = CountedNote.decodes.withLock { $0 }
        let notesRevision = store.revision(of: CountedNote.self)

        // A save, a delete and an import of lifts leave the notes' decoded cache alone.
        var heavier = bench
        heavier.reps = 3
        heavier.updatedAt = t0 + 1
        store.save(heavier)
        store.delete(Lift.self, id: bench.id)
        let backup = BackupFile(
            app: .liftTrack,
            records: [
                BackupRecord(
                    kind: Lift.kind, uuid: UUID(), updatedAt: t0, schemaVersion: 2,
                    payload: try payload(Lift(name: "Row", updatedAt: t0)), deleted: false)
            ])
        try store.importBackup(SystemJSON.encoder().encode(backup), app: .liftTrack, shared: nil)
        #expect(store.all(CountedNote.self).count == 1000)
        #expect(CountedNote.decodes.withLock { $0 } == decoded, "no note was decoded again")
        #expect(store.revision(of: CountedNote.self) == notesRevision)
        #expect(store.revision(of: Lift.self) == store.revision)
        #expect(store.all(Lift.self).map(\.name) == ["Row"])

        // Saving a note patches the notes in, decoding only that one; erasing moves every kind.
        store.save(CountedNote(text: "One more", updatedAt: t0 + 2000))
        #expect(store.all(CountedNote.self).count == 1001)
        #expect(CountedNote.decodes.withLock { $0 } == decoded + 1)
        #expect(store.revision(of: CountedNote.self) == store.revision)
        store.eraseAll()
        #expect(store.revision(of: CountedNote.self) == store.revision)
        #expect(store.revision(of: Lift.self) == store.revision)
        #expect(store.all(CountedNote.self).isEmpty)
    }

    @Test func importRefusesAnotherAppsBackup() throws {
        let source = memoryStore()
        source.save(Lift(name: "Bench", updatedAt: t0))
        let macroBackup = try source.exportBackup(app: .macroTrack, shared: nil)

        let store = memoryStore()
        let shared = temporarySharedContainer()
        #expect(throws: SystemStoreError.backupFromOtherApp(.macroTrack)) {
            try store.importBackup(macroBackup, app: .knowledge, shared: shared)
        }
        #expect(store.revision == 0)
        #expect(store.rows(kind: Lift.kind).isEmpty, "no foreign row reaches this app's database")
        #expect(SystemStoreError.backupFromOtherApp(.macroTrack).errorDescription == "This backup is from Stadig Macro. Restore it there.")
        #expect(try store.importBackup(macroBackup, app: .macroTrack, shared: shared).records == 1)
    }

    @Test func aSharedFileFailureAfterTheRecordsStillRefreshes() throws {
        let store = memoryStore()
        let stale = store.all(Lift.self)
        #expect(stale.isEmpty)
        let lift = Lift(name: "Bench", updatedAt: t0)
        // "core" as a file and as a folder: valid paths, but the second can't be written.
        let damaged = BackupFile(
            app: .liftTrack,
            records: [
                BackupRecord(
                    kind: Lift.kind, uuid: lift.id, updatedAt: t0, schemaVersion: 2,
                    payload: try payload(lift), deleted: false)
            ],
            shared: ["core": Data("{}".utf8), "core/x.json": Data("{}".utf8)])
        let revision = store.revision
        #expect(throws: (any Error).self) {
            try store.importBackup(SystemJSON.encoder().encode(damaged), app: .liftTrack, shared: temporarySharedContainer())
        }
        #expect(store.revision > revision, "the records were saved, so the store says it changed")
        #expect(store.all(Lift.self) == [lift])
    }

    @Test func asyncExportAndImportRoundTrip() async throws {
        let store = memoryStore()
        let lifts = (0..<40).map { Lift(name: "Lift \($0)", updatedAt: t0 + Double($0)) }
        store.save(lifts)
        let shared = temporarySharedContainer()
        try shared.write(AppSummary(app: .liftTrack, updated: t0), to: .summary(.liftTrack), by: .liftTrack)
        let backup = try await store.exportBackup(app: .liftTrack, shared: shared)
        let file = try BackupFile(data: backup)
        #expect(file.app == .liftTrack)
        #expect(file.records.count == 40)
        #expect(Set(file.shared.keys) == ["apps/liftTrack/summary.json"])

        let restored = memoryStore()
        let summary = try await restored.importBackup(backup, app: .liftTrack, shared: temporarySharedContainer())
        #expect(summary == BackupSummary(records: 40, kinds: ["lift": 40], sharedFiles: 1))
        #expect(restored.all(Lift.self) == store.all(Lift.self))
        await #expect(throws: SystemStoreError.backupFromOtherApp(.liftTrack)) {
            try await restored.importBackup(backup, app: .knowledge, shared: nil)
        }
    }

    @Test func bulkSavesFollowTheSameRules() throws {
        // More than 32 records take the bulk path, which reads every row of the kind once.
        let store = memoryStore()
        let ids = (0..<40).map { _ in UUID() }
        store.save(ids.map { Lift(id: $0, name: "First", reps: 5, updatedAt: t0 + 10) })
        #expect(store.rows(kind: Lift.kind).count == 40)

        // A duplicate row from another device, and a row from a newer app version.
        let duplicate = ids[1]
        let future = ids[2]
        store.insertRawRow(
            kind: Lift.kind, uuid: duplicate, updatedAt: t0, schemaVersion: 2,
            payload: try payload(Lift(id: duplicate, name: "Old copy", updatedAt: t0)))
        let futurePayload = Data(#"{"id":"\#(future.uuidString)","name":"Clean","reps":2,"notes":"","updatedAt":1760000020000,"tempo":"31X1"}"#.utf8)
        store.insertRawRow(kind: Lift.kind, uuid: future, updatedAt: t0 + 20, schemaVersion: 3, payload: futurePayload)

        var batch = ids.map { Lift(id: $0, name: "Older", reps: 1, updatedAt: t0) }  // all older: ignored
        batch += ids.map { Lift(id: $0, name: "Second", reps: 8, updatedAt: t0 + 30) }
        batch.append(Lift(id: ids[0], name: "Newest in the batch", updatedAt: t0 + 40))
        batch.append(Lift(id: ids[0], name: "Older in the batch", updatedAt: t0 + 35))
        store.save(batch)

        #expect(store.get(Lift.self, id: ids[0])?.name == "Newest in the batch", "the newest of two copies in one batch wins")
        #expect(store.get(Lift.self, id: ids[3])?.name == "Second")
        #expect(store.rows(kind: Lift.kind).filter { $0.uuid == duplicate }.allSatisfy { $0.updatedAt == t0 + 30 }, "duplicate rows converge")
        let futureRow = try #require(store.rows(kind: Lift.kind).first { $0.uuid == future && $0.schemaVersion == 3 })
        #expect(futureRow.payload == futurePayload, "a newer app version's copy isn't overwritten")
        #expect(store.rows(kind: Lift.kind).count == 42, "upserts, not inserts")
        #expect(store.all(Lift.self).count == 39, "the newer-version record stays unreadable here")
    }

    @Test func deletionsStickAtTheirEdges() throws {
        let store = memoryStore()
        // Another device's clock was a day ahead: the deletion still lands after its edit.
        let ahead = Lift(name: "From the future", updatedAt: t0 + 86_400 * 365 * 10)
        store.save(ahead)
        store.delete(Lift.self, id: ahead.id)
        let tombstone = try #require(store.rows(kind: Lift.kind).first)
        #expect(tombstone.deleted)
        #expect(tombstone.updatedAt.wholeMilliseconds == ahead.updatedAt.wholeMilliseconds + 1)
        #expect(store.get(Lift.self, id: ahead.id) == nil)

        // A save stamped before the deletion loses.
        var earlier = ahead
        earlier.updatedAt = Date(wholeMilliseconds: tombstone.updatedAt.wholeMilliseconds - 1)
        let revision = store.revision
        store.save(earlier)
        #expect(store.get(Lift.self, id: ahead.id) == nil)
        #expect(store.revision == revision)
        // One in the deletion's own millisecond was made after it (delete, then save under the same
        // id, as Stadig Macro's day status does): it comes back, in every row, so no device keeps the tombstone.
        var sameInstant = ahead
        sameInstant.updatedAt = tombstone.updatedAt
        store.save(sameInstant)
        #expect(store.get(Lift.self, id: ahead.id) == sameInstant)
        #expect(store.rows(kind: Lift.kind).allSatisfy { !$0.deleted })
    }

    @Test func deleteThenSaveUnderTheSameIDKeepsTheSave() {
        // Stadig Macro's setState deletes a day's status and at once saves the new one under the same
        // id, usually in the deletion's own millisecond.
        let store = memoryStore()
        let ids = (0..<25).map { _ in UUID() }
        store.save(ids.map { Lift(id: $0, name: "Bench", reps: 5, updatedAt: t0) })
        for id in ids {
            store.delete(Lift.self, id: id)
            store.save(Lift(id: id, name: "Bench", reps: 8, updatedAt: Date()))
        }
        #expect(ids.allSatisfy { store.get(Lift.self, id: $0)?.reps == 8 })
    }

    @Test func payloadsSurviveABackupByteForByte() throws {
        struct Odd: Codable {
            var text = "Crème brûlée / 日本語 \"quoted\" \\ back\nline"
            var big: Int64 = 9_007_199_254_740_993
            var negative = -42
            var tiny = 1e-7
            var fraction = 0.1
            var whole = 100.0
            var flags = [true, false]
            var nested: [String: [Double]] = ["b": [1.5, -2], "a": []]
            var nothing: String?
            var updatedAt = t0
        }
        var encoded = try SystemJSON.encoder().encode(Odd())
        // An explicit null, which the encoder leaves out but an older writer might not, in its sorted place.
        encoded = Data(String(decoding: encoded, as: UTF8.self).replacingOccurrences(of: #","text":"#, with: #","nothing":null,"text":"#).utf8)
        #expect(String(decoding: encoded, as: UTF8.self).contains("null"))
        let payloads = [
            encoded,
            Data("[1,2,3]".utf8),
            Data([0xFF, 0x00, 0x7B]),  // not JSON at all: embeds as base64
            Data(#""a bare string""#.utf8),
        ]
        for original in payloads {
            let record = BackupRecord(kind: "odd", uuid: UUID(), updatedAt: t0, schemaVersion: 1, payload: original, deleted: false)
            let file = BackupFile(app: .liftTrack, records: [record])
            let read = try BackupFile(data: SystemJSON.encoder(pretty: true).encode(file))
            #expect(read.records.first?.payload == original, "\(String(decoding: original, as: UTF8.self))")
        }
    }
}
