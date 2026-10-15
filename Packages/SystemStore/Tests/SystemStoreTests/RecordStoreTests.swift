import Foundation
import SystemCore
import Testing
@testable import SystemStore

@MainActor
struct RecordStoreTests {
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
        store.save([Lift(id: id, name: "Bench", reps: 1, updatedAt: t0 + 15),
                    Lift(id: id, name: "Bench", reps: 10, updatedAt: t0 + 40),
                    Lift(id: id, name: "Bench", reps: 9, updatedAt: t0 + 30)])
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
        store.insertRawRow(kind: Lift.kind, uuid: id, updatedAt: t0, schemaVersion: 1,
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
        store.insertRawRow(kind: Lift.kind, uuid: squatID, updatedAt: t0, schemaVersion: 1,
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
        let summary = try store.importBackup(backup, shared: restoredShared)
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
        let again = try store.importBackup(backup, shared: nil)
        #expect(again == BackupSummary())
        #expect(store.get(Lift.self, id: bench.id) == pausedBench)

        // An older local copy is replaced by the backup's.
        let other = memoryStore()
        var oldRow = row
        oldRow.name = "Row (old)"
        oldRow.updatedAt = t0 - 60
        other.save(oldRow)
        let merged = try other.importBackup(backup, shared: nil)
        #expect(merged.records == 3)
        #expect(other.get(Lift.self, id: row.id) == row)
    }

    @Test func importRefusesWhatIsntABackup() throws {
        let store = memoryStore()
        #expect(throws: SystemStoreError.notABackup) { try store.importBackup(Data("{}".utf8), shared: nil) }
        #expect(throws: SystemStoreError.notABackup) { try store.importBackup(Data("not json".utf8), shared: nil) }
        let future = Data(#"{"format":"system-backup","formatVersion":99,"app":"liftTrack","created":0,"records":[],"shared":{}}"#.utf8)
        #expect(throws: SystemStoreError.backupFromNewerVersion(formatVersion: 99)) { try store.importBackup(future, shared: nil) }

        // A bad shared path fails the import before anything is written.
        let lift = Lift(name: "Bench", updatedAt: t0)
        let hostile = BackupFile(app: .liftTrack, records: [BackupRecord(kind: Lift.kind, uuid: lift.id, updatedAt: t0, schemaVersion: 2,
                                                                        payload: try payload(lift), deleted: false)],
                                 shared: ["../outside.json": Data("{}".utf8)])
        let data = try SystemJSON.encoder().encode(hostile)
        #expect(throws: SystemStoreError.invalidPath("../outside.json")) { try store.importBackup(data, shared: temporarySharedContainer()) }
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

    @Test func cloudKitStoreThatCantOpenFallsBackWithoutCrashing() {
        // The test runner has no bundle identifier or iCloud entitlement.
        let store = RecordStore(name: "cloud-\(UUID().uuidString)", cloudKitContainer: "iCloud.dev.svindland.systemstore.tests",
                                inMemory: false, directory: temporaryDirectory())
        #expect(store.syncStatus == "This device only")
        let lift = Lift(name: "Bench", updatedAt: t0)
        store.save(lift)
        #expect(store.get(Lift.self, id: lift.id) == lift)
    }

    @Test func remoteChangeBumpsTheRevision() async throws {
        let store = RecordStore(name: "remote-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: false, directory: temporaryDirectory())
        let url = try #require(store.storeFileURL)
        let before = store.revision
        let name = Notification.Name("NSPersistentStoreRemoteChangeNotification")
        // A burst of notifications coalesces into one refresh; another store's are ignored.
        for _ in 0..<3 { NotificationCenter.default.post(name: name, object: nil, userInfo: ["storeURL": url]) }
        NotificationCenter.default.post(name: name, object: nil, userInfo: ["storeURL": URL(filePath: "/tmp/other.store")])
        for _ in 0..<40 where store.revision == before {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(400))
        #expect(store.revision == before + 1)
    }
}
