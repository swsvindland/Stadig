import Foundation
import Synchronization
import Testing

@testable import SystemStore

/// A record kind that counts its decodes, for these tests alone, so parallel tests don't share the count.
struct RemoteNote: StoredRecord, Equatable {
    static let kind = "remote-note"
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

/// Another device's changes, as CloudKit imports them: a second store on the same file writes, and
/// the first hears of it by the remote-change notification. The counts of decodes are why these
/// run one at a time.
@MainActor @Suite(.serialized)
struct RemoteChangeTests {
    private static func decodes() -> Int { RemoteNote.decodes.withLock { $0 } }

    /// Two stores over one file, the first with `count` notes and a lift, both kinds read.
    private func stores(notes count: Int) -> (here: RecordStore, elsewhere: RecordStore, notes: [RemoteNote], lift: Lift) {
        let directory = temporaryDirectory()
        let name = "remote-\(UUID().uuidString)"
        let here = RecordStore(name: name, cloudKitContainer: nil, inMemory: false, directory: directory)
        let notes = (0..<count).map { RemoteNote(text: "Note \($0)", updatedAt: t0 + Double($0)) }
        let lift = Lift(name: "Bench", updatedAt: t0)
        here.save(notes)
        here.save(lift)
        _ = here.all(RemoteNote.self)
        _ = here.all(Lift.self)
        let elsewhere = RecordStore(name: name, cloudKitContainer: nil, inMemory: false, directory: directory)
        return (here, elsewhere, notes, lift)
    }

    /// Posts the remote-change notification and waits for `store`'s observers to hear of it.
    private func deliver(to store: RecordStore) async throws {
        let calls = Counter()
        let token = store.observeChanges { calls.value += 1 }
        let url = try #require(store.storeFileURL)
        NotificationCenter.default.post(
            name: Notification.Name("NSPersistentStoreRemoteChangeNotification"), object: nil, userInfo: ["storeURL": url])
        for _ in 0..<100 where calls.value == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(calls.value == 1)
        withExtendedLifetime(token) {}
    }

    @Test func aRemoteChangeDecodesOnlyTheRecordsItTouched() async throws {
        let (here, elsewhere, notes, lift) = stores(notes: 300)
        let liftRevision = here.revision(of: Lift.self)
        var edited = notes[5]
        edited.text = "Edited on the phone"
        edited.updatedAt = t0 + 1000
        let added = RemoteNote(text: "Logged on the phone", updatedAt: t0 + 1001)
        elsewhere.save(edited)
        elsewhere.save(added)
        elsewhere.delete(RemoteNote.self, id: notes[7].id)
        let before = Self.decodes()

        try await deliver(to: here)

        let all = here.all(RemoteNote.self)
        #expect(Self.decodes() == before + 2, "the edit and the new note, not 300 notes")
        #expect(all.count == 300)
        #expect(all.prefix(2) == [added, edited], "newest first, as a fresh read orders them")
        #expect(!all.contains { $0.id == notes[7].id })
        #expect(all == here.uncachedAll(RemoteNote.self))
        #expect(here.revision(of: RemoteNote.self) == here.revision)
        #expect(here.revision(of: Lift.self) == liftRevision, "a kind the change didn't touch isn't read again")
        #expect(here.all(Lift.self) == [lift])
    }

    @Test func aLosingSecondCopyLeavesTheRecordAsItWas() async throws {
        // Two devices made the same record before syncing: CloudKit delivers an older copy as a
        // second row, and the newer one still speaks for it.
        let (here, elsewhere, notes, _) = stores(notes: 10)
        let older = RemoteNote(id: notes[3].id, text: "An older copy", updatedAt: t0 - 60)
        elsewhere.insertRawRow(
            kind: RemoteNote.kind, uuid: older.id, updatedAt: older.updatedAt, schemaVersion: 1,
            payload: try SystemJSON.encoder().encode(older))

        try await deliver(to: here)

        #expect(here.all(RemoteNote.self) == notes.reversed())
        #expect(here.all(RemoteNote.self) == here.uncachedAll(RemoteNote.self))
    }

    @Test func rowsRemovedOutrightReadEveryKindAgain() async throws {
        // An erase removes the rows themselves, and history doesn't say which kinds they were.
        let (here, elsewhere, _, _) = stores(notes: 10)
        let liftRevision = here.revision(of: Lift.self)
        elsewhere.eraseAll()

        try await deliver(to: here)

        #expect(here.revision(of: Lift.self) > liftRevision)
        #expect(here.all(Lift.self).isEmpty)
        #expect(here.all(RemoteNote.self).isEmpty)
    }

    @Test func aBigImportReadsEveryKindAgain() async throws {
        // A new device's first sync: past the limit, reading whole is quicker than patching.
        let (here, elsewhere, _, lift) = stores(notes: 10)
        let liftRevision = here.revision(of: Lift.self)
        let more = (0..<(RecordStore.remotePatchLimit + 1)).map { RemoteNote(text: "More \($0)", updatedAt: t0 + 5000 + Double($0)) }
        elsewhere.save(more)

        try await deliver(to: here)

        #expect(here.revision(of: Lift.self) > liftRevision)
        #expect(here.all(RemoteNote.self).count == 10 + more.count)
        #expect(here.all(RemoteNote.self) == here.uncachedAll(RemoteNote.self))
        #expect(here.all(Lift.self) == [lift])
    }
}
