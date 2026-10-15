import Foundation
import LiftEngine

/// JSON the way SystemJSON writes it (SystemStore isn't linked into the Watch): dates as whole
/// milliseconds since 1970, keys sorted, so payloads read the same on both ends of the link.
nonisolated enum WatchJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64((date.timeIntervalSince1970 * 1000).rounded()))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSince1970: try container.decode(Double.self) / 1000)
        }
        return decoder
    }
}

/// A countdown or stopwatch the Watch is running for one item: a timed drill or conditioning.
nonisolated struct ItemTimer: Codable, Hashable, Sendable {
    var item: UUID
    var set: Int
    var started: Date
}

/// The session in progress and what the Watch keeps alongside it. Saved after every change so a
/// relaunch picks up where the person left off.
nonisolated struct StoredSession: Codable, Sendable {
    var live: LiveSession
    /// The context the session started from. History is dropped: logging never reads it.
    var context: PhoneContext
    /// An item picked from the exercise list, done ahead of the plan's order.
    var focus: UUID?
    var timer: ItemTimer?
    /// The person chose to end before every item was done.
    var wrappingUp = false
}

/// Small JSON files in Application Support.
nonisolated enum WatchStorage {
    static let context = "context.json"
    static let session = "session.json"
    static let outbox = "outbox.json"

    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "LiftTrack", directoryHint: .isDirectory)
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
        return try? WatchJSON.decoder().decode(type, from: data)
    }

    static func save(_ value: some Encodable, to name: String) {
        guard let data = try? WatchJSON.encoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appending(path: name), options: .atomic)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: name))
    }
}
