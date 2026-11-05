import Foundation
import SystemCore
import SystemStore

// The hub's own records. Kinds never change once shipped; bump a schemaVersion (and teach `migrate`)
// when a record's shape changes.

/// The rhythm, as the one record that holds it. `hub/rhythm.json` is what the other apps read; this
/// is what comes back after a reinstall.
struct RhythmRecord: StoredRecord, Hashable {
    static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-0000000040B1") ?? UUID()
    static var kind: String { "rhythm" }
    static var schemaVersion: Int { 1 }

    var id: UUID
    var rhythm: Rhythm
    var updatedAt: Date

    init(_ rhythm: Rhythm) {
        id = Self.singletonID
        self.rhythm = rhythm
        updatedAt = rhythm.updated
    }
}

/// A change as a record of its own: the change's `kind` is a word for what happened, which a stored
/// record's static `kind` would hide.
struct DayChangeRecord: StoredRecord, Hashable {
    static var kind: String { "day-change" }
    static var schemaVersion: Int { 1 }

    var id: UUID
    var change: DayChange
    var updatedAt: Date

    init(_ change: DayChange) {
        id = change.id
        self.change = change
        updatedAt = change.updatedAt
    }
}
