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

    /// Whether an App Group this process isn't entitled to is unavailable here. The Mac checks the
    /// sandbox; an iOS simulator may hand out any group's folder.
    static let unentitledGroupIsUnavailable: Bool = {
        #if os(macOS)
        true
        #else
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.dev.svindland.stadig.tests.unentitled") == nil
        #endif
    }()

    @Test(.enabled(if: unentitledGroupIsUnavailable, "this platform hands out App Groups without the entitlement"))
    func fallsBackWithoutTheAppGroup() {
        let directory = temporaryDirectory()
        let shared = SharedContainer(groupID: "group.dev.svindland.stadig.tests.\(UUID().uuidString)", fallbackDirectory: directory)
        #expect(!shared.isAppGroup)
        #expect(shared.directory == directory)
    }

    @Test func anExplicitDirectoryIsUsedAsGiven() throws {
        // Never the App Group, wherever this runs: a test or an in-memory launch never shares with the apps.
        let directory = temporaryDirectory().appending(path: "not yet made", directoryHint: .isDirectory)
        let shared = SharedContainer(directory: directory)
        #expect(!shared.isAppGroup)
        #expect(shared.directory == directory)
        #expect(shared.allFiles().isEmpty)
        #expect(shared.read(.profile) == nil)

        let profile = SharedProfile(createdBy: .liftTrack, createdAt: t0, updatedAt: t0)
        try shared.write(profile, to: .profile, by: .liftTrack)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "core/profile.json").path(percentEncoded: false)))
        #expect(SharedContainer(directory: directory).read(.profile) == profile)
        #expect(Set(shared.allFiles().keys) == ["core/profile.json"])
        try shared.remove(.profile)
        #expect(shared.read(.profile) == nil)
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
        try writeRaw(
            [
                "schemaVersion": 1, "writtenBy": "hub", "writtenAt": t0.wholeMilliseconds,
                "payload": [["body": "Deload next week"], ["body": "Sleep"]],
            ],
            to: Self.notes.path, in: shared)

        #expect(shared.read(Self.notes) == [Note(text: "Deload next week", pinned: false), Note(text: "Sleep", pinned: false)])
        let envelope = try #require(shared.envelope(Self.notes))
        #expect(envelope.schemaVersion == 2)
        #expect(envelope.writtenBy == .hub)
        #expect(envelope.writtenAt == t0)
    }

    @Test func newerSchemaIsNeitherReadNorOverwritten() throws {
        let shared = temporarySharedContainer()
        try writeRaw(
            [
                "schemaVersion": 3, "writtenBy": "hub", "writtenAt": t0.wholeMilliseconds,
                "payload": ["notes": [["text": "From the future", "pinned": true, "colour": "red"]]],
            ],
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
        let calendar = SystemCalendar(currentBlock: nil, deloads: [], checkIns: [], updated: t0, publishedBy: .liftTrack)
        try source.write(profile, to: .profile, by: .liftTrack)
        try source.write(calendar, to: .calendar, by: .liftTrack)
        try source.write(AppSummary(app: .liftTrack, updated: t0), to: .summary(.liftTrack), by: .liftTrack)
        // A file nothing has a key for any more (the hub's) goes along by its path.
        try writeRaw(
            ["schemaVersion": 1, "writtenBy": "hub", "writtenAt": t0.wholeMilliseconds, "payload": ["wake": 360, "bed": 1350]],
            to: "hub/rhythm.json", in: source)
        try Data("ignored".utf8).write(to: source.directory.appending(path: ".DS_Store"))

        let files = source.allFiles()
        #expect(Set(files.keys) == ["core/profile.json", "core/calendar.json", "hub/rhythm.json", "apps/liftTrack/summary.json"])

        let target = temporarySharedContainer()
        try target.restore(files)
        #expect(target.read(.profile) == profile)
        #expect(target.read(.calendar) == calendar)
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

    /// Stadig Macro's summary as it was before fasts, to read a file the way an older Stadig Lift does.
    struct NutritionBeforeFasts: Codable, Sendable, Equatable {
        var phase: NutritionPhase?
        var maintenanceKcal: Double?
        var days: [NutritionDay]
    }

    @Test func theNutritionSummarysFastIsReadByNewAppsAndSkippedByOld() throws {
        let shared = SharedContainer(directory: temporaryDirectory())
        let day = Day(year: 2026, month: 10, day: 19)
        let days = [NutritionDay(day: day, logged: true, proteinHit: true, caloriesHit: false)]
        // Written before fasts (no "fast" key): read as no fast.
        try shared.write(NutritionSummary(phase: nil, maintenanceKcal: 2600, days: days), to: .nutrition, by: .macroTrack)
        let raw = try String(contentsOf: shared.directory.appending(path: "apps/macroTrack/nutrition.json"), encoding: .utf8)
        #expect(!raw.contains("\"fast\""))
        #expect(shared.read(.nutrition)?.fast == nil && shared.read(.nutrition)?.maintenanceKcal == 2600)
        // With a fast: read back whole, and still readable by an app that doesn't know fasts.
        let fast = PublishedFast(start: t0, goalHours: 36)
        try shared.write(NutritionSummary(phase: nil, maintenanceKcal: 2600, days: days, fast: fast), to: .nutrition, by: .macroTrack)
        #expect(shared.read(.nutrition)?.fast == fast)
        let older = SharedKey<NutritionBeforeFasts>(path: "apps/macroTrack/nutrition.json", schemaVersion: 1)
        #expect(shared.read(older) == NutritionBeforeFasts(phase: nil, maintenanceKcal: 2600, days: days))
        #expect(fast.goalEnd == t0.addingTimeInterval(36 * 3600) && fast.hours(at: t0.addingTimeInterval(5400)) == 1.5)
    }

    @Test func writeIfChangedSkipsTheSameContent() throws {
        let shared = temporarySharedContainer()
        let url = shared.directory.appending(path: "apps/liftTrack/summary.json")
        func strength(_ score: Double) -> StatReading {
            StatReading(stat: .strength, score: score, label: "Intermediate", trend: .onPace, updated: t0)
        }
        var summary = AppSummary(app: .liftTrack, updated: t0, stats: [strength(40)])

        #expect(try shared.writeIfChanged(summary, to: .summary(.liftTrack), by: .liftTrack, stamp: \.updated, now: t0 + 60))
        #expect(shared.read(.summary(.liftTrack))?.updated == t0 + 60, "stamped when written")
        let written = try Data(contentsOf: url)

        // The same content made a moment later, sub-millisecond dates and all, isn't written again.
        summary.updated = Date()
        summary.stats[0].updated = t0 + 0.0004
        #expect(try !shared.writeIfChanged(summary, to: .summary(.liftTrack), by: .liftTrack, stamp: \.updated, now: t0 + 120))
        #expect(try Data(contentsOf: url) == written)

        summary.stats[0].score = 41
        #expect(try shared.writeIfChanged(summary, to: .summary(.liftTrack), by: .liftTrack, stamp: \.updated, now: t0 + 180))
        #expect(shared.read(.summary(.liftTrack)) == AppSummary(app: .liftTrack, updated: t0 + 180, stats: [strength(41)]))

        // Several stamps: carried over for the comparison, and only the summary's moved on a write.
        summary.stats[0].updated = t0 + 999
        let carry: (inout AppSummary, AppSummary) -> Void = { new, old in
            new.updated = old.updated
            for i in new.stats.indices {
                new.stats[i].updated = old.stats.first { $0.stat == new.stats[i].stat }?.updated ?? new.stats[i].updated
            }
        }
        #expect(
            try !shared.writeIfChanged(
                summary, to: .summary(.liftTrack), by: .liftTrack, now: t0 + 240,
                carryOver: carry, stamp: { $0.updated = $1 }))
    }

    @Test func writeIfChangedUpgradesAnOlderFile() throws {
        let shared = temporarySharedContainer()
        try writeRaw(
            [
                "schemaVersion": 1, "writtenBy": "hub", "writtenAt": t0.wholeMilliseconds,
                "payload": [["body": "Sleep"]],
            ],
            to: Self.notes.path, in: shared)
        // The same notes, but the file is at schema 1: rewritten so it's at 2 on disk.
        let notes = [Note(text: "Sleep", pinned: false)]
        #expect(try shared.writeIfChanged(notes, to: Self.notes, by: .liftTrack, now: t0, carryOver: { _, _ in }, stamp: { _, _ in }))
        #expect(shared.envelope(Self.notes)?.writtenBy == .liftTrack)
        #expect(try !shared.writeIfChanged(notes, to: Self.notes, by: .liftTrack, now: t0, carryOver: { _, _ in }, stamp: { _, _ in }))
    }

    @MainActor
    @Test func writesNotifyObservers() async throws {
        final class Counter { var value = 0 }
        let counter = Counter()
        let token = SharedContainer.observeChanges { counter.value += 1 }
        let shared = temporarySharedContainer()
        try shared.write([LifeModePeriod](), to: .lifeModes, by: .liftTrack)
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

        #expect(
            table.text == "Exercise,Note,kg\r\n"
                + "\"Bench, paused\",\"Said \"\"go\"\"\",100\r\n"
                + "Squat,\"line one\nline two\",140.5\r\n"
                + "Row,\"crlf\r\ninside\",\r\n"
                + "\" Dip\",Ünïcødé – ×,-5\r\n")
        #expect(Array(table.data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(decoding: table.data.dropFirst(3), as: UTF8.self) == table.text)
    }

    @Test func formulasAreNeutralized() {
        var table = CSVTable(header: ["Food", "Brand", "kcal"])
        table.append(["+Proteinas", "@ Ease", "-5"])
        table.append(["=HYPERLINK(\"http://x\",\"Open\")", "-foo", "-0.5"])
        table.append(["-1+cmd|' /C calc'!A0", "\tTabbed", "+2.5"])
        table.append(["Ünïcødé = fine", "a-b", "1e-3"])

        #expect(
            table.text == "Food,Brand,kcal\r\n"
                + "'+Proteinas,'@ Ease,-5\r\n"
                + "\"'=HYPERLINK(\"\"http://x\"\",\"\"Open\"\")\",'-foo,-0.5\r\n"
                + "'-1+cmd|' /C calc'!A0,'\tTabbed,+2.5\r\n"
                + "Ünïcødé = fine,a-b,1e-3\r\n")
    }

    @Test func emptyTableIsJustTheHeader() {
        #expect(CSVTable(header: ["a", "b"]).text == "a,b\r\n")
    }
}
