import Foundation
import SystemCore

/// The NIH Dietary Supplement Label Database, offline: US supplement labels by barcode and by name,
/// with their Supplement Facts. Built by `Scripts/build-supplement-catalog.py` into `supplements.db`,
/// which the app bundles when it's there. Read-only and thread-safe.
public final class SupplementCatalog: Sendable {
    public let version: String
    public let attribution: String
    /// Labels in the file.
    public let count: Int
    private let pool: ConnectionPool

    private static let columns = "id, name, brand, barcode, serving, data"

    public init(url: URL) throws {
        pool = try ConnectionPool(url: url)
        var meta: [String: String] = [:]
        var count = 0
        try pool.with { connection in
            try connection.query("SELECT key, value FROM catalog_meta") { row in
                if let key = row.string(0), let value = row.string(1) { meta[key] = value }
            }
            try connection.query("SELECT count(*) FROM supplements") { row in count = Int(row.int(0)) }
        }
        guard let version = meta["version"] else { throw SQLiteError(code: 0, message: "\(url.lastPathComponent) has no catalog version") }
        self.version = version
        attribution = meta["attribution"] ?? ""
        self.count = count
    }

    /// `supplements.db` from the app bundle, when it ships one.
    public static func standard() -> SupplementCatalog? {
        Bundle.main.url(forResource: "supplements", withExtension: "db").flatMap { try? SupplementCatalog(url: $0) }
    }

    /// A label by any barcode form (UPC-A, EAN-13, UPC-E…).
    public func supplement(barcode: String, symbology: Barcode.Symbology? = nil) -> SupplementFacts? {
        for key in Barcode.keys(for: barcode, symbology: symbology) {
            if let found = first("SELECT \(Self.columns) FROM supplements WHERE barcode = ? LIMIT 1", [.integer(Int64(key) ?? -1)]) {
                return found
            }
        }
        return nil
    }

    /// A label by id: "dsld:12345".
    public func supplement(id: String) -> SupplementFacts? {
        guard id.hasPrefix("dsld:"), let number = Int64(id.dropFirst(5)) else { return nil }
        return first("SELECT \(Self.columns) FROM supplements WHERE id = ? LIMIT 1", [.integer(number)])
    }

    /// Labels whose name and brand hold every word typed (the last as a prefix), the ones on the
    /// market first, then the best full-text matches.
    public func search(_ query: String, limit: Int = 30) -> [SupplementFacts] {
        let words = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty, words.joined().count >= 2 else { return [] }
        let expression = words.enumerated().map { i, word in i == words.count - 1 ? "\"\(word)\"*" : "\"\(word)\"" }.joined(separator: " ")
        var found: [SupplementFacts] = []
        try? pool.with { connection in
            try connection.query("""
                SELECT \(Self.columns) FROM (
                  SELECT rowid, bm25(supplement_search, 3.0, 1.0) AS score FROM supplement_search WHERE supplement_search MATCH ? LIMIT 400
                ) AS hit JOIN supplements ON supplements.id = hit.rowid
                ORDER BY supplements.market DESC, hit.score LIMIT ?
                """, [.text(expression), .integer(Int64(limit))]) { row in
                if let facts = Self.facts(row) { found.append(facts) }
            }
        }
        return found
    }

    private func first(_ sql: String, _ parameters: [SQLValue]) -> SupplementFacts? {
        var found: SupplementFacts?
        try? pool.with { connection in
            try connection.query(sql, parameters) { row in found = found ?? Self.facts(row) }
        }
        return found
    }

    private static func facts(_ row: SQLRow) -> SupplementFacts? {
        guard let name = row.string(1) else { return nil }
        let serving = SupplementServing.parse(row.string(4) ?? "") ?? (1, "serving")
        let lines = row.string(5).flatMap { JSONValue.parse($0)?.array } ?? []
        let ingredients = lines.compactMap { line -> SupplementIngredient? in
            guard let parts = line.array, parts.count >= 3, let name = parts[0].string else { return nil }
            return SupplementIngredient(name: name, amount: parts[1].number, unit: parts[2].string ?? "")
        }
        let brand = row.string(2)
        return SupplementFacts(id: "dsld:\(row.int(0))", name: name, brand: brand?.isEmpty == false ? brand : nil,
                               barcode: row.isNull(3) ? nil : barcodeKey(String(row.int(3))), servingCount: serving.count,
                               unit: serving.unit, ingredients: ingredients, source: .dsld)
    }
}
