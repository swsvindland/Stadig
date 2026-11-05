import Foundation
import MindEngine
import SystemCore
import SystemStore

// Stadig Mind's records in its own CloudKit-synced database. Kinds never change once shipped;
// bump a schemaVersion (and teach `migrate`) when a record's shape changes.

nonisolated extension MindSettings: @retroactive StoredRecord {
    public static var kind: String { "settings" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension WeekSettings: @retroactive StoredRecord {
    public static var kind: String { "week-settings" }
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
    /// 2: the period can be a tombstone (`deletedAt`). A build that knows only 1 would save it back
    /// without the delete, so it leaves these alone; version 1 payloads read as they are.
    public static var schemaVersion: Int { 2 }
}

nonisolated extension WritingPiece: @retroactive StoredRecord {
    public static var kind: String { "writing-piece" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension BlindComparison: @retroactive StoredRecord {
    public static var kind: String { "blind-comparison" }
    public static var schemaVersion: Int { 1 }
}

nonisolated extension BookMeta: @retroactive StoredRecord {
    public static var kind: String { "book-meta" }
    public static var schemaVersion: Int { 1 }
}
