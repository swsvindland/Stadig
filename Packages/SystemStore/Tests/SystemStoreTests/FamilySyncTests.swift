import Foundation
import SystemCore
import Testing

@testable import SystemStore

/// Two devices: each its own shared container, both mirroring one family database (CloudKit's, as
/// far as each device can tell).
@MainActor
struct FamilySyncTests {
    let family = memoryStore()

    func device() -> FamilySync {
        FamilySync(shared: temporarySharedContainer(), store: family)
    }

    func profile(goals: [OutcomeGoal], at date: Date) -> SharedProfile {
        SharedProfile(goals: goals, createdBy: .liftTrack, createdAt: t0, updatedAt: date)
    }

    /// Writes a file as an app would, with the envelope's `writtenAt` set to `date`.
    func write<T>(_ value: T, to key: SharedKey<T>, by app: AppID, at date: Date, in shared: SharedContainer) throws {
        let envelope = SharedEnvelope(schemaVersion: key.schemaVersion, writtenBy: app, writtenAt: date, payload: value)
        let url = shared.directory.appending(path: key.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SystemJSON.encoder().encode(envelope).write(to: url)
    }

    @Test func aFileWrittenOnOneDeviceReachesAnother() throws {
        let phone = device()
        let mac = device()
        try phone.shared.write(profile(goals: [.stronger], at: t0), to: .profile, by: .liftTrack)
        #expect(phone.push() == 1)
        #expect(mac.pull() == 1)
        #expect(mac.shared.read(.profile) == phone.shared.read(.profile))
        #expect(mac.shared.allFiles() == phone.shared.allFiles())
        // The copy that came down is already the database's: nothing goes back up.
        #expect(mac.push() == 0)
    }

    @Test func theNewerCopyWinsInBothDirections() throws {
        let phone = device()
        let mac = device()
        try write(profile(goals: [.stronger], at: t0), to: .profile, by: .liftTrack, at: t0, in: phone.shared)
        phone.push()
        // The Mac's own copy is newer: it stays, and it's the one that goes up.
        try write(profile(goals: [.leaner], at: t0), to: .profile, by: .knowledge, at: t0 + 60, in: mac.shared)
        #expect(mac.pull() == 0)
        #expect(mac.shared.read(.profile)?.goals == [.leaner])
        #expect(mac.push() == 1)
        #expect(phone.pull() == 1)
        #expect(phone.shared.read(.profile)?.goals == [.leaner])
        // An older copy on the phone doesn't go up over it.
        try write(profile(goals: [.healthier], at: t0), to: .profile, by: .liftTrack, at: t0 + 30, in: phone.shared)
        #expect(phone.push() == 0)
        #expect(phone.pull() == 1)
        #expect(phone.shared.read(.profile)?.goals == [.leaner])
    }

    @Test func aFileAtANewerSchemaIsNeverReplaced() throws {
        let phone = device()
        let mac = device()
        try write(profile(goals: [.stronger], at: t0), to: .profile, by: .liftTrack, at: t0 + 60, in: phone.shared)
        phone.push()
        // The Mac runs a newer app version that wrote the profile at a schema this one doesn't know.
        let newer = SharedKey<SharedProfile>(path: "core/profile.json", schemaVersion: SharedProfile.schemaVersion + 1)
        try write(profile(goals: [.leaner], at: t0), to: newer, by: .knowledge, at: t0, in: mac.shared)
        #expect(mac.pull() == 0)
        #expect(mac.shared.envelope(newer)?.schemaVersion == SharedProfile.schemaVersion + 1)
    }

    @Test func aBadPathFromTheDatabaseIsSkippedAndTheRestStillComeDown() throws {
        let mac = device()
        let good = try SystemJSON.encoder().encode(
            SharedEnvelope(
                schemaVersion: 1, writtenBy: .liftTrack, writtenAt: t0,
                payload: SystemCalendar(currentBlock: nil, deloads: [], checkIns: [], updated: t0, publishedBy: .liftTrack)))
        family.save([
            SharedFileRecord(path: "../outside.json", contents: good, updatedAt: t0),
            SharedFileRecord(path: "core/calendar.json", contents: good, updatedAt: t0),
        ])
        #expect(mac.pull() == 1)
        #expect(Set(mac.shared.allFiles().keys) == ["core/calendar.json"])
    }

    @Test func onlyEnvelopesGoUp() throws {
        let phone = device()
        let stray = phone.shared.directory.appending(path: "notes/readme.txt")
        try FileManager.default.createDirectory(at: stray.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not an envelope".utf8).write(to: stray)
        #expect(phone.push() == 0)
        #expect(family.all(SharedFileRecord.self).isEmpty)
    }

    @Test func eachPathIsOneRecordWhoeverUploadsIt() throws {
        let lift = device()
        let mind = device()
        try write(profile(goals: [.stronger], at: t0), to: .profile, by: .liftTrack, at: t0, in: lift.shared)
        try write(profile(goals: [.stronger], at: t0), to: .profile, by: .knowledge, at: t0 + 1, in: mind.shared)
        lift.push()
        mind.push()
        #expect(family.all(SharedFileRecord.self).count == 1)
        #expect(SharedFileRecord.id(for: "core/profile.json") == SharedFileRecord.id(for: "core/profile.json"))
        #expect(SharedFileRecord.id(for: "core/profile.json") != SharedFileRecord.id(for: "core/calendar.json"))
    }

    @Test func startingUpBringsDownWhatsThereAndSendsUpWhatsNew() throws {
        let phone = device()
        try phone.shared.write(
            SystemCalendar(currentBlock: nil, deloads: [], checkIns: [], updated: t0, publishedBy: .liftTrack), to: .calendar, by: .liftTrack)
        phone.push()
        // A device whose disk has a file the database lacks, starting after the phone's upload.
        let shared = temporarySharedContainer()
        try shared.write(profile(goals: [.leaner], at: t0), to: .profile, by: .macroTrack)
        let ipad = FamilySync(shared: shared, store: family)
        #expect(Set(ipad.shared.allFiles().keys) == ["core/calendar.json", "core/profile.json"])
        #expect(Set(family.all(SharedFileRecord.self).map(\.path)) == ["core/calendar.json", "core/profile.json"])
    }
}
