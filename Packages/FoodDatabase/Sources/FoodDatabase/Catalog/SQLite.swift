import Foundation
import SQLite3
import Synchronization
import os

let catalogLog = Logger(subsystem: "dev.svindland.stadig.macro", category: "catalog")

/// A value bound to a statement parameter.
enum SQLValue {
    case text(String)
    case integer(Int64)
    case real(Double)
}

struct SQLiteError: Error, CustomStringConvertible {
    var code: Int32
    var message: String
    var description: String { "SQLite \(code): \(message)" }
}

/// The row a statement is on, read in place.
struct SQLRow {
    fileprivate let statement: OpaquePointer

    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }
    func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }

    func string(_ column: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, column) else { return nil }
        return String(decoding: UnsafeBufferPointer(start: text, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
    }

    /// The column's UTF-8 bytes, valid only inside the row callback.
    func withBytes<T>(_ column: Int32, _ body: (UnsafeBufferPointer<UInt8>) throws -> T) rethrows -> T? {
        guard let text = sqlite3_column_text(statement, column) else { return nil }
        return try body(UnsafeBufferPointer(start: text, count: Int(sqlite3_column_bytes(statement, column))))
    }
}

/// One read-only connection to a catalog file, used by one thread at a time (see `ConnectionPool`),
/// with its prepared statements kept.
final class SQLiteConnection: @unchecked Sendable {
    private let handle: OpaquePointer
    private var statements: [String: OpaquePointer] = [:]

    /// Opens the file in place, read-only and immutable: nothing is copied, locked or journaled.
    init(url: URL) throws {
        var components = URLComponents()
        components.scheme = "file"
        components.path = url.path
        components.queryItems = [URLQueryItem(name: "immutable", value: "1")]
        let uri = components.string ?? "file:\(url.path)?immutable=1"
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        let code = sqlite3_open_v2(uri, &handle, flags, nil)
        guard code == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close_v2(handle)
            throw SQLiteError(code: code, message: message)
        }
        self.handle = handle
    }

    deinit {
        for statement in statements.values { sqlite3_finalize(statement) }
        sqlite3_close_v2(handle)
    }

    /// Frees the pages this connection has cached.
    func releaseMemory() { sqlite3_db_release_memory(handle) }

    private func prepared(_ sql: String) throws -> OpaquePointer {
        if let statement = statements[sql] { return statement }
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v3(handle, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &statement, nil)
        guard code == SQLITE_OK, let statement else { throw SQLiteError(code: code, message: String(cString: sqlite3_errmsg(handle))) }
        statements[sql] = statement
        return statement
    }

    /// Runs a query, calling `row` for each result row.
    func query(_ sql: String, _ parameters: [SQLValue] = [], row: (SQLRow) throws -> Void) throws {
        let statement = try prepared(sql)
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        for (i, parameter) in parameters.enumerated() {
            let index = Int32(i + 1)
            switch parameter {
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
            case .integer(let value): sqlite3_bind_int64(statement, index, value)
            case .real(let value): sqlite3_bind_double(statement, index, value)
            }
        }
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return }
            guard code == SQLITE_ROW else { throw SQLiteError(code: code, message: String(cString: sqlite3_errmsg(handle))) }
            try row(SQLRow(statement: statement))
        }
    }
}

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Connections to one file, handed to one thread at a time; more open as threads need them, and
/// up to `kept` stay open for the next call. Each has its own page cache (up to 8 MB over the
/// packaged-food catalog), so the burst of a meal's parallel lookups doesn't keep them all.
final class ConnectionPool: Sendable {
    let url: URL
    /// As many as one typed search runs against a catalog at once.
    let kept: Int
    private let idle: Mutex<[SQLiteConnection]>
    /// Reads that failed. A failed search reads as no results, so this is how tests see one.
    let failures = Atomic<Int>(0)

    init(url: URL, kept: Int = 4) throws {
        self.url = url
        self.kept = max(1, kept)
        idle = Mutex([try SQLiteConnection(url: url)])
    }

    /// Connections open between calls.
    var idleCount: Int { idle.withLock { $0.count } }

    func with<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        let connection = try idle.withLock { $0.popLast() } ?? SQLiteConnection(url: url)
        defer { idle.withLock { if $0.count < kept { $0.append(connection) } } }
        return try body(connection)
    }

    /// A read whose failure the caller shows as nothing found: logged and counted, not thrown.
    func read(_ body: (SQLiteConnection) throws -> Void) {
        do {
            try with(body)
        } catch {
            failures.add(1, ordering: .relaxed)
            catalogLog.error("\(self.url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Closes every idle connection but one and empties that one's page cache.
    func trim() {
        idle.withLock { idle in
            if idle.count > 1 { idle.removeSubrange(1...) }
            idle.first?.releaseMemory()
        }
    }
}
