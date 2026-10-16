import Foundation
import Synchronization

/// One catalog file, open read-only in place: USDA's generic foods or Open Food Facts' packaged ones.
final class Catalog: Sendable {
    enum Kind: Sendable { case generic, branded }

    /// A food a full-text match found, and whether it is sold only in other countries.
    struct Hit: Sendable {
        var entry: Entry
        var away: Bool
        var food: Food { entry.food }
    }

    let kind: Kind
    let version: String
    let license: String
    let attribution: String
    let source: String
    /// Rows, counted by the last rowid: catalogs are written once, in order.
    let foods: Int
    /// The order version 3 rows keep nutrient values in; nil for object rows.
    let order: [String]?
    private let pool: ConnectionPool
    private let barcodeIsInteger: Bool
    private let matchSQL: String
    /// Rows already read this launch, by rowid: each keystroke finds most of the last one's foods.
    private let read = Mutex<[Int64: Entry]>([:])

    private static let columns = "foods.rowid, foods.id, foods.name, foods.brand, foods.barcode, foods.data, foods.popularity"

    /// Opens a catalog and reads its metadata; throws when the file isn't a catalog.
    init(url: URL, kind: Kind, region: String?) throws {
        self.kind = kind
        pool = try ConnectionPool(url: url)
        var meta: [String: String] = [:]
        var markets = false
        var integerBarcodes = false
        var foods = 0
        try pool.with { connection in
            try connection.query("SELECT key, value FROM catalog_meta") { row in
                if let key = row.string(0), let value = row.string(1) { meta[key] = value }
            }
            try connection.query("SELECT name, type FROM pragma_table_info('foods')") { row in
                if row.string(0) == "markets" { markets = true }
                if row.string(0) == "barcode" { integerBarcodes = row.string(1)?.uppercased() == "INTEGER" }
            }
            try connection.query("SELECT max(rowid) FROM foods") { row in foods = Int(row.int(0)) }
        }
        guard let version = meta["version"] else { throw SQLiteError(code: 0, message: "\(url.lastPathComponent) has no catalog version") }
        self.version = version
        license = meta["license"] ?? ""
        attribution = meta["attribution"] ?? ""
        source = meta["source"] ?? ""
        self.foods = foods
        order = meta["nutrients"].flatMap { JSONValue.parse($0)?.array?.compactMap(\.string) }
        barcodeIsInteger = integerBarcodes
        // A brand's recipe differs between countries (US and French Oreos), so a packaged food sold
        // only elsewhere ranks below the foods sold here; one whose countries aren't known isn't one.
        let away: String
        if markets, let region {
            let sold = { (market: String) in "instr(' ' || foods.markets || ' ', ' \(market) ')" }
            away = "(foods.markets <> '' AND \(sold(region)) = 0 AND \(sold("world")) = 0)"
        } else {
            away = "0"
        }
        // Names starting with the lead word come before the full-text ranking, then the foods sold
        // in the phone's region, and among packaged foods the ones scanned more often come sooner.
        matchSQL = """
            SELECT \(Self.columns), \(away) AS away FROM (
              SELECT rowid, bm25(food_search, 3.0, 1.0) AS score FROM food_search WHERE food_search MATCH ? LIMIT ?
            ) AS hit
            JOIN foods ON foods.rowid = hit.rowid
            ORDER BY foods.name LIKE ? DESC, away, hit.score - 0.5 * foods.popularity
            LIMIT ?
            """
    }

    var foodSource: FoodSource { kind == .generic ? .usda : .off }

    /// A row of `columns` as a food.
    private func food(_ row: SQLRow) -> Food? {
        guard let name = row.string(2) else { return nil }
        let barcode = row.isNull(4) ? nil : barcodeKey(barcodeIsInteger ? String(row.int(4)) : row.string(4))
        let id: String
        if kind == .branded, let barcode {
            id = "off:\(barcode)"
        } else if let stored = row.string(1) {
            id = stored
        } else {
            return nil
        }
        guard let data = row.withBytes(5, { RowData(data: $0, order: order) }) ?? nil else { return nil }
        let brand = row.string(3)
        return Food(id: id, name: name, brand: brand?.isEmpty == false ? brand : nil, barcode: barcode, basis: data.basis,
                    nutrients: data.nutrients, extras: data.extras, portions: data.portions, source: foodSource,
                    popularity: row.isNull(6) ? 0 : row.double(6))
    }

    /// How many matches a catalog ranks. Millions of packaged foods match "ch" or "chicken", so only
    /// the first matches in row order, the most scanned, are ranked; the generic catalog is small
    /// enough to rank whole.
    private var candidates: Int { kind == .generic ? -1 : 1000 }

    /// Runs a full-text expression. Names starting with `lead` come first.
    func match(_ expression: String, limit: Int, lead: String = "") -> [Hit] {
        var hits: [Hit] = []
        var fresh: [(Int64, Entry)] = []
        try? pool.with { connection in
            try connection.query(matchSQL, [.text(expression), .integer(Int64(candidates)), .text(lead.isEmpty ? "" : "\(lead)%"),
                                            .integer(Int64(limit))]) { row in
                let rowid = row.int(0)
                if let entry = read.withLock({ $0[rowid] }) {
                    hits.append(Hit(entry: entry, away: row.int(7) == 1))
                } else if let food = food(row) {
                    let entry = Entry(food)
                    fresh.append((rowid, entry))
                    hits.append(Hit(entry: entry, away: row.int(7) == 1))
                }
            }
        }
        if !fresh.isEmpty {
            read.withLock { read in
                if read.count + fresh.count > 6000 { read.removeAll(keepingCapacity: true) }
                for (rowid, entry) in fresh { read[rowid] = entry }
            }
        }
        return hits
    }

    /// How many foods an expression matches, counting no further than `cap`.
    func count(_ expression: String, cap: Int = 2000) -> Int {
        var found = 0
        try? pool.with { connection in
            try connection.query("SELECT count(*) FROM (SELECT rowid FROM food_search WHERE food_search MATCH ? LIMIT ?)",
                                 [.text(expression), .integer(Int64(cap))]) { row in found = Int(row.int(0)) }
        }
        return found
    }

    /// Rows of the `terms` vocabulary: each word the catalog knows and how many foods use it.
    func terms(_ sql: String, _ parameters: [SQLValue]) -> [(term: String, foods: Int)] {
        var rows: [(term: String, foods: Int)] = []
        try? pool.with { connection in
            try connection.query(sql, parameters) { row in
                if let term = row.string(0) { rows.append((term, Int(row.int(1)))) }
            }
        }
        return rows
    }

    /// The food stored under a 14-digit barcode key.
    func food(barcode key: String) -> Food? {
        let value: SQLValue = barcodeIsInteger ? .integer(Int64(key) ?? -1) : .text(key)
        return first("SELECT \(Self.columns) FROM foods WHERE barcode = ? LIMIT 1", [value])
    }

    /// The food with a stored id.
    func food(id: String) -> Food? {
        first("SELECT \(Self.columns) FROM foods WHERE id = ? LIMIT 1", [.text(id)])
    }

    private func first(_ sql: String, _ parameters: [SQLValue]) -> Food? {
        var found: Food?
        try? pool.with { connection in
            try connection.query(sql, parameters) { row in found = found ?? food(row) }
        }
        return found
    }
}
