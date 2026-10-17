import Foundation
import MindEngine
import SystemCore
import SystemStore

// Mind Track's records in its own CloudKit-synced database. Kinds never change once shipped;
// bump a schemaVersion (and teach `migrate`) when a record's shape changes.

nonisolated extension MindSettings: @retroactive StoredRecord {
    public static var kind: String { "settings" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension MemoryCard: @retroactive StoredRecord {
    public static var kind: String { "card" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension StudySession: @retroactive StoredRecord {
    public static var kind: String { "session" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension TestResult: @retroactive StoredRecord {
    public static var kind: String { "test" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension Book: @retroactive StoredRecord {
    public static var kind: String { "book" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension Reflection: @retroactive StoredRecord {
    public static var kind: String { "reflection" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension LifeModeRecord: @retroactive StoredRecord {
    public static var kind: String { "life-mode" }
    public static var schemaVersion: Int { 1 }
}
