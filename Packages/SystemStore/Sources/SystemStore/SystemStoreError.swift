import Foundation
import SystemCore

/// Why a store, backup or shared-container operation refused or failed.
public enum SystemStoreError: Error, LocalizedError, Sendable, Equatable {
    /// No database could be opened, not even in memory.
    case storeUnavailable
    /// The data isn't a System backup file.
    case notABackup
    /// The backup was written by a newer version of the app.
    case backupFromNewerVersion(formatVersion: Int)
    /// The backup was written by another of the apps; it restores only there.
    case backupFromOtherApp(AppID)
    /// A stored record was written by a newer version of the app than this one understands.
    case newerRecordSchema(kind: String, stored: Int, known: Int)
    /// A shared file on disk was written with a newer schema than this app knows; it isn't overwritten.
    case newerSharedSchema(path: String, onDisk: Int, known: Int)
    /// A payload that should be a JSON object isn't one.
    case payloadNotAnObject(kind: String)
    /// A shared-container path that is empty, absolute or climbs out of the container.
    case invalidPath(String)

    public var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            "The database couldn't be opened."
        case .notABackup:
            "This file isn't a backup from The System."
        case .backupFromNewerVersion:
            "This backup was made by a newer version of the app. Update the app, then restore it."
        case .backupFromOtherApp(let app):
            "This backup is from \(app.displayName). Restore it there."
        case .newerRecordSchema(let kind, _, _):
            "Some \(kind) data was saved by a newer version of the app. Update the app to read it."
        case .newerSharedSchema(let path, _, _):
            "\(path) was written by a newer version of one of the apps, so it wasn't overwritten."
        case .payloadNotAnObject(let kind):
            "A \(kind) record is damaged."
        case .invalidPath(let path):
            "\"\(path)\" isn't a valid shared file path."
        }
    }
}
