import Foundation
import SystemCore
import Testing
@testable import SystemStore

struct SharedContainerTests {
    struct Note: Codable, Sendable, Equatable {
        var text: String
        var pinned: Bool
    }

    /// Version 1 stored notes as `{"body": ...}`; version 2 renamed it to `text` and added `pinned`.
    static let notes = SharedKey<[Note]>(path: "test/notes.json", schemaVersion: 2) { json, version in
        if version == 1, let payload = json["payload"] as? [[String: Any]] {
            json["payload"] = payload.map { note in
                var note = note
                note["text"] = note.removeValue(forKey: "body")
                note["pinned"] = false
                return note
            }
        }
    }

    func writeRaw(_ object: [String: Any], to path: String, in shared: SharedContainer) throws {
        let url = shared.directory.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    @Test func fallsBackWithoutTheAppGroup() {
        let directory = temporaryDirectory()
        let shared = SharedContainer(groupID: "group.dev.svindland.stadig.tests.\(UUID().uuidString)", fallbackDirectory: directory)
        #expect(!shared.isAppGroup)
        #expect(shared.directory == directory)
    }

    @Test func writeReadRoundTripInAnEnvelope() throws {
        let shared = temporarySharedContainer()
        let profile = SharedProfile(goals: [.stronger], createdBy: .liftTrack, createdAt: t0, updatedAt: t0)
        let before = Date()
        try shared.write(profile, to: .profile, by: .liftTrack)

        #expect(shared.read(.profile) == profile)
        let envelope = try #require(shared.envelope(.profile))
        #expect(envelope.schemaVersion == SharedProfile.schemaVersion)
        #expect(envelope.writtenBy == .liftTrack)
        #expect(envelope.writtenAt.wholeMilliseconds >= before.wholeMilliseconds)

        let onDisk = try Data(contentsOf: shared.directory.appending(path: "core/profile.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: onDisk) as? [String: Any])
        #expect(Set(json.keys) == ["payload", "schemaVersion", "writtenAt", "writtenBy"])
        #expect(json["writtenBy"] as? String == "liftTrack")

        let summary = AppSummary(app: .liftTrack, updated: t0)
        try shared.write(summary, to: .summary(.liftTrack), by: .liftTrack)
        #expect(shared.read(.summary(.liftTrack)) == summary)
        #expect(FileManager.default.fileExists(atPath: shared.directory.appending(path: "apps/liftTrack/summary.json").path(percentEncoded: false)))
        #expect(shared.read(.summary(.macroTrack)) == nil)

        try shared.remove(.summary(.liftTrack))
        #expect(shared.read(.summary(.liftTrack)) == nil)
        try shared.remove(.summary(.liftTrack))
    }

    @Test func olderEnvelopeIsMigratedStepByStep() throws {
        let shared = temporarySharedContainer()
        try writeRaw(["schemaVersion": 1, "writtenBy": "hub", "writtenAt": t0.wholeMilliseconds,
                      "payload": [["body": "Deload next week"], ["body": "Sleep"]]],
                     to: Self.notes.path, in: shared)

        #expect(shared.read(Self.notes) == [Note(text: "Deload next week", pinned: false), Note(text: "Sleep", pinned: false)])
        let envelope = try #require(shared.envelope(Self.notes))
        #expect(envelope.schemaVersion == 2)
        #expect(envelope.writtenBy == .hub)
        #expect(envelope.writtenAt == t0)
    }

    @Test func newerSchemaIsNeitherReadNorOverwritten() throws {
        let shared = temporarySharedContainer()
        try writeRaw(["schemaVersion": 3, "writtenBy": "hub", "writtenAt": t0.wholeMilliseconds,
                      "payload": ["notes": [["text": "From the future", "pinned": true, "colour": "red"]]]],
                     to: Self.notes.path, in: shared)
        let url = shared.directory.appending(path: Self.notes.path)
        let original = try Data(contentsOf: url)

        #expect(shared.read(Self.notes) == nil)
        #expect(throws: SystemStoreError.newerSharedSchema(path: "test/notes.json", onDisk: 3, known: 2)) {
            try shared.write([Note(text: "Mine", pinned: false)], to: Self.notes, by: .liftTrack)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func allFilesRestoreRoundTrip() throws {
        let source = temporarySharedContainer()
        let profile = SharedProfile(createdBy: .liftTrack, createdAt: t0, updatedAt: t0)
        let recommendation = Recommendation(to: .liftTrack, kind: .deloadNow, subject: nil, reason: "Fatigue is high", created: t0)
        try source.write(profile, to: .profile, by: .liftTrack)
        try source.write([recommendation], to: .recommendations, by: .hub)
        try source.write(AppSummary(app: .liftTrack, updated: t0), to: .summary(.liftTrack), by: .liftTrack)
        try Data("ignored".utf8).write(to: source.directory.appending(path: ".DS_Store"))

        let files = source.allFiles()
        #expect(Set(files.keys) == ["core/profile.json", "hub/recommendations.json", "apps/liftTrack/summary.json"])

        let target = temporarySharedContainer()
        try target.restore(files)
        #expect(target.read(.profile) == profile)
        #expect(target.read(.recommendations) == [recommendation])
        #expect(target.allFiles() == files)

        // Restoring merges: a copy on disk written after the backup's stays.
        let newer = SharedProfile(goals: [.stronger], createdBy: .macroTrack, createdAt: t0, updatedAt: t0 + 60)
        try target.write(newer, to: .profile, by: .macroTrack)
        let older = SharedEnvelope(schemaVersion: 1, writtenBy: .liftTrack, writtenAt: t0, payload: profile)
        #expect(try target.merge(["core/profile.json": SystemJSON.encoder().encode(older)]) == 0)
        #expect(target.read(.profile) == newer)

        // Paths that escape the container are refused, and nothing is written.
        #expect(throws: SystemStoreError.invalidPath("../escape.json")) {
            try target.restore(["ok.json": Data("{}".utf8), "../escape.json": Data("{}".utf8)])
        }
        #expect(!FileManager.default.fileExists(atPath: target.directory.appending(path: "ok.json").path(percentEncoded: false)))
        for path in ["", "/etc/hosts", "a//b.json", "./a.json", "a/../../b.json"] {
            #expect(throws: SystemStoreError.invalidPath(path)) { try target.restore([path: Data()]) }
        }
    }

    @MainActor
    @Test func writesNotifyObservers() async throws {
        final class Counter { var value = 0 }
        let counter = Counter()
        let token = SharedContainer.observeChanges { counter.value += 1 }
        let shared = temporarySharedContainer()
        try shared.write([Quest](), to: .hubQuests, by: .hub)
        for _ in 0..<40 where counter.value == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(counter.value >= 1)
        withExtendedLifetime(token) {}
    }
}

struct CSVTableTests {
    @Test func quotesCommasQuotesAndLineBreaks() {
        var table = CSVTable(header: ["Exercise", "Note", "kg"])
        table.append(["Bench, paused", "Said \"go\"", "100"])
        table.append(["Squat", "line one\nline two", "140.5"])
        table.append(["Row", "crlf\r\ninside"])
        table.append([" Dip", "Ünïcødé – ×", "-5"])

        #expect(table.text == "Exercise,Note,kg\r\n"
            + "\"Bench, paused\",\"Said \"\"go\"\"\",100\r\n"
            + "Squat,\"line one\nline two\",140.5\r\n"
            + "Row,\"crlf\r\ninside\",\r\n"
            + "\" Dip\",Ünïcødé – ×,-5\r\n")
        #expect(Array(table.data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(decoding: table.data.dropFirst(3), as: UTF8.self) == table.text)
    }

    @Test func emptyTableIsJustTheHeader() {
        #expect(CSVTable(header: ["a", "b"]).text == "a,b\r\n")
    }
}
