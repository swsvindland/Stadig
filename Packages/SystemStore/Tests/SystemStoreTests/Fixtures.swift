import Foundation
@testable import SystemStore

/// A record at schema version 2. Version 1 called the lift's name `title` and had no `notes`.
struct Lift: StoredRecord, Equatable {
    static let kind = "lift"
    static let schemaVersion = 2

    var id: UUID
    var name: String
    var reps: Int
    var notes: String
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, reps: Int = 5, notes: String = "", updatedAt: Date) {
        self.id = id
        self.name = name
        self.reps = reps
        self.notes = notes
        self.updatedAt = updatedAt
    }

    static func migrate(_ json: inout [String: Any], from version: Int) throws {
        if version == 1 {
            json["name"] = json.removeValue(forKey: "title")
            json["notes"] = ""
        }
    }
}

/// A fixed, millisecond-exact instant, so records compare equal after a round trip.
let t0 = Date(timeIntervalSince1970: 1_760_000_000)

func payload(_ lift: Lift) throws -> Data {
    try SystemJSON.encoder().encode(lift)
}

/// The v1 shape of a lift, as an older app version stored it.
func v1Payload(id: UUID, title: String, reps: Int, updatedAt: Date) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "id": id.uuidString, "title": title, "reps": reps, "updatedAt": updatedAt.wholeMilliseconds,
    ] as [String: Any])
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "SystemStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A shared container in a fresh temporary directory.
func temporarySharedContainer() -> SharedContainer {
    SharedContainer(directory: temporaryDirectory())
}

@MainActor
func memoryStore() -> RecordStore {
    RecordStore(name: "test-\(UUID().uuidString)", cloudKitContainer: nil, inMemory: true)
}
