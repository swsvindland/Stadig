import Foundation
import OSLog

let storeLog = Logger(subsystem: "dev.svindland.stadig", category: "store")

/// The JSON coding every System payload, shared file and backup uses.
///
/// Dates are milliseconds since 1970 (the `.millisecondsSince1970` wire format), written as whole
/// numbers so a date always survives a round trip exactly and newest-wins comparisons never flip on
/// a rounding error. Any number of milliseconds, fractional or not, decodes. Keys are sorted, so the
/// same value always encodes to the same bytes.
public enum SystemJSON {
    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting =
            pretty
            ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.wholeMilliseconds)
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSince1970: try container.decode(Double.self) / 1000)
        }
        return decoder
    }
}

extension Date {
    /// Whole milliseconds since 1970: the precision every newest-wins comparison uses.
    var wholeMilliseconds: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }

    init(wholeMilliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(wholeMilliseconds) / 1000)
    }

    /// This date, rounded to the millisecond, as it reads back after a round trip through SystemJSON.
    var roundedToMilliseconds: Date { Date(wholeMilliseconds: wholeMilliseconds) }
}

/// Any JSON value, so a backup can embed payloads and shared files as readable JSON instead of base64.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Decodable can't ask a value's type, so each miss is a thrown error: the common leaf types go
    /// first (a payload is mostly strings and numbers), integers before doubles so they stay whole.
    /// JSONDecoder never reads a number as a Bool or the other way round, so the order is safe.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// Bytes that are JSON (an object or array) embed as that JSON; anything else as a base64 string.
/// Decoding takes a string as base64 and re-encodes anything else, so either form reads back.
struct EmbeddedJSONData: Codable, Sendable {
    var data: Data

    init(_ data: Data) { self.data = data }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let base64 = try? container.decode(String.self) {
            guard let data = Data(base64Encoded: base64) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not valid base64.")
            }
            self.data = data
        } else {
            self.data = try SystemJSON.encoder().encode(try container.decode(JSONValue.self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if !data.isEmpty, let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            switch value {
            case .object, .array:
                try container.encode(value)
                return
            default: break
            }
        }
        try container.encode(data.base64EncodedString())
    }
}
