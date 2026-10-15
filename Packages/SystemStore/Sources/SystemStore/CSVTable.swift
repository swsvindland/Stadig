import Foundation

/// CSV that opens cleanly in Numbers and Excel: RFC 4180 quoting, CRLF line ends, UTF-8.
public struct CSVTable: Sendable {
    public private(set) var header: [String]
    public private(set) var rows: [[String]] = []

    public init(header: [String]) {
        self.header = header
    }

    /// Adds a row. A row shorter than the header is padded with empty fields.
    public mutating func append(_ row: [String]) {
        rows.append(row.count < header.count ? row + Array(repeating: "", count: header.count - row.count) : row)
    }

    /// The table as CSV text: every line, the last included, ends in CRLF.
    public var text: String {
        ([header] + rows).map { $0.map(Self.field).joined(separator: ",") + "\r\n" }.joined()
    }

    /// The text as UTF-8 with a byte-order mark, which Excel needs to read it as UTF-8 rather than
    /// the system's legacy encoding. Numbers ignores the mark.
    public var data: Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    /// Quotes a field that holds a comma, quote, line break or edge whitespace, doubling its quotes.
    /// Checked by scalar: Swift treats "\r\n" as one Character, so `contains("\n")` would miss it.
    static func field(_ value: String) -> String {
        let needsQuotes = value.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
            || value.first?.isWhitespace == true || value.last?.isWhitespace == true
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
