import Foundation
import Testing
import SystemCore
@testable import SystemStore

/// Life modes travel between the apps with their tombstones, and files the apps wrote before
/// tombstones existed still read.
@Suite("Shared life modes")
struct LifeModeSharingTests {
    func container() -> SharedContainer {
        let directory = FileManager.default.temporaryDirectory.appending(path: "life-modes-\(UUID().uuidString)", directoryHint: .isDirectory)
        return SharedContainer(directory: directory)
    }

    @Test func aDeleteTravelsAsATombstone() throws {
        let shared = container()
        let trip = LifeModePeriod(kind: .vacation, start: Day(year: 2026, month: 11, day: 1), end: Day(year: 2026, month: 11, day: 8),
                                  createdBy: .liftTrack)
        try shared.write([trip.deleted()], to: .lifeModes, by: .liftTrack)
        let read = try #require(shared.read(.lifeModes))
        #expect(read.count == 1 && read[0].isDeleted)
        #expect(LifeModePeriod.merge([[trip], read]).live.isEmpty, "the delete beats the older live copy another app holds")
    }

    @Test func aFileFromBeforeTombstonesStillReads() throws {
        let shared = container()
        // What an app built before tombstones writes: the same path at schema 1.
        let before = SharedKey<[LifeModePeriod]>(path: SharedKey<[LifeModePeriod]>.lifeModes.path, schemaVersion: 1)
        let trip = LifeModePeriod(kind: .vacation, start: Day(year: 2026, month: 11, day: 1), end: Day(year: 2026, month: 11, day: 8),
                                  createdBy: .macroTrack)
        try shared.write([trip], to: before, by: .macroTrack)
        let read = try #require(shared.read(.lifeModes))
        #expect(read.map(\.id) == [trip.id])
        #expect(!read[0].isDeleted)
    }
}
