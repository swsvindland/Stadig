import Foundation
import LiftEngine
import OSLog

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
    var timer: ItemTimer?
    /// The person chose to end before every item was done.
    var wrappingUp = false
}

/// Small JSON files in Application Support.
nonisolated enum WatchStorage {
    static let context = "context.json"
    static let session = "session.json"
    static let outbox = "outbox.json"

    static let log = Logger(subsystem: "dev.svindland.stadig.lift.watchkitapp", category: "storage")

    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "LiftTrack", directoryHint: .isDirectory)
    }

    /// The file's value, or nil when there's none. A file that's there but doesn't decode (written
    /// by a build with another shape, say) is moved aside first, so the next save can't write over
    /// sessions still waiting in it and a later build can read them back. One that can't be read at
    /// all is left for the next read (locked until the first unlock after a restart, say), unless the
    /// caller is about to write over it: then it's moved aside too.
    static func load<T: Decodable>(_ type: T.Type, from name: String, settingAsideUnreadable: Bool = false) -> T? {
        let url = directory.appending(path: name)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            if settingAsideUnreadable {
                log.error("Couldn't read \(name, privacy: .public), so it's set aside before it's written over: \(error.localizedDescription)")
                setAside(url)
            } else {
                log.error("Couldn't read \(name, privacy: .public): \(error.localizedDescription)")
            }
            return nil
        }
        do {
            return try WatchJSON.decoder().decode(type, from: data)
        } catch {
            log.error("\(name, privacy: .public) doesn't decode, so it's set aside: \(String(describing: error))")
            setAside(url)
            return nil
        }
    }

    static func save(_ value: some Encodable, to name: String) {
        do {
            let data = try WatchJSON.encoder().encode(value)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appending(path: name), options: .atomic)
        } catch {
            log.error("Couldn't save \(name, privacy: .public): \(error.localizedDescription)")
        }
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: name))
    }

    /// "outbox.json" becomes "outbox.unreadable-1760000000.json", next to it.
    private static func setAside(_ url: URL) {
        let name = "\(url.deletingPathExtension().lastPathComponent).unreadable-\(Int(Date().timeIntervalSince1970)).json"
        do {
            try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appending(path: name))
        } catch {
            log.error("Couldn't set \(url.lastPathComponent, privacy: .public) aside: \(error.localizedDescription)")
        }
    }
}
