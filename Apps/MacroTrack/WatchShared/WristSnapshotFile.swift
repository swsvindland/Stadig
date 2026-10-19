import Foundation
import NutritionEngine
import OSLog

/// Where the Watch app leaves the complications' snapshot: its App Group on the Watch, which the
/// iPhone's App Group never reaches, so it's the Watch's own numbers either way.
nonisolated enum WristSnapshotFile {
    static let groupID = "group.dev.svindland.stadig"
    private static let log = Logger(subsystem: "dev.svindland.stadig.macro.watchkitapp", category: "snapshot")

    static var appGroupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appending(path: "MacroTrack", directoryHint: .isDirectory).appending(path: "watch.json")
    }

    /// The snapshot at `url`; empty before the first one, or when it can't be read.
    static func load(from url: URL? = appGroupURL) -> WristSnapshot {
        guard let url else { return .empty }
        do {
            return WristSnapshot.decoded(try Data(contentsOf: url)) ?? .empty
        } catch CocoaError.fileReadNoSuchFile {
            return .empty
        } catch {
            log.error("Couldn't read the snapshot: \(error.localizedDescription)")
            return .empty
        }
    }

    /// Writes `snapshot` unless the file already says the same, apart from when it was written.
    /// Returns whether it wrote, so the app reloads the complications only then.
    @discardableResult
    static func save(_ snapshot: WristSnapshot, to url: URL? = appGroupURL) -> Bool {
        guard let url else { return false }
        if let data = try? Data(contentsOf: url), let old = WristSnapshot.decoded(data), !snapshot.differs(from: old) { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try snapshot.encoded().write(to: url, options: .atomic)
            return true
        } catch {
            // The complications keep the last snapshot; the next change tries again.
            log.error("Couldn't save the snapshot: \(error.localizedDescription)")
            return false
        }
    }
}
