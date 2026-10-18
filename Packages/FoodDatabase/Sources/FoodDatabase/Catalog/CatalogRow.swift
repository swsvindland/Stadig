import Foundation
import SystemCore

/// A parsed JSON value; the catalogs' `data` column is small JSON, read on every search.
enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    var number: Double? { if case .number(let value) = self { value } else { nil } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
    var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }

    /// Parses UTF-8 JSON, or nil when it isn't valid.
    static func parse(_ bytes: UnsafeBufferPointer<UInt8>) -> JSONValue? {
        var reader = JSONReader(bytes: bytes)
        guard let value = reader.value() else { return nil }
        reader.skipSpace()
        return reader.index == bytes.count ? value : nil
    }

    static func parse(_ text: String) -> JSONValue? {
        var text = text
        return text.withUTF8 { parse($0) }
    }
}

private struct JSONReader {
    let bytes: UnsafeBufferPointer<UInt8>
    var index = 0

    mutating func skipSpace() {
        while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x0A || bytes[index] == 0x0D || bytes[index] == 0x09 {
            index += 1
        }
    }

    mutating func value() -> JSONValue? {
        skipSpace()
        guard index < bytes.count else { return nil }
        switch bytes[index] {
        case UInt8(ascii: "["):
            index += 1
            var items: [JSONValue] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                guard let item = value() else { return nil }
                items.append(item)
                skipSpace()
                guard index < bytes.count else { return nil }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                return nil
            }
        case UInt8(ascii: "{"):
            index += 1
            var members: [String: JSONValue] = [:]
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
            while true {
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\""), let key = string() else { return nil }
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
                index += 1
                guard let item = value() else { return nil }
                members[key] = item
                skipSpace()
                guard index < bytes.count else { return nil }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
                return nil
            }
        case UInt8(ascii: "\""):
            return string().map(JSONValue.string)
        case UInt8(ascii: "n"):
            return literal("null", .null)
        case UInt8(ascii: "t"):
            return literal("true", .bool(true))
        case UInt8(ascii: "f"):
            return literal("false", .bool(false))
        default:
            return number().map(JSONValue.number)
        }
    }

    private mutating func literal(_ word: StaticString, _ value: JSONValue) -> JSONValue? {
        let count = word.utf8CodeUnitCount
        guard index + count <= bytes.count else { return nil }
        for i in 0..<count where bytes[index + i] != word.utf8Start[i] { return nil }
        index += count
        return value
    }

    private mutating func number() -> Double? {
        let start = index
        var negative = false
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") { negative = true; index += 1 }
        var mantissa: UInt64 = 0
        var digits = 0
        var scale = 0
        var exact = true
        while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
            if digits < 18 { mantissa = mantissa * 10 + UInt64(bytes[index] - 0x30); digits += 1 } else { exact = false }
            index += 1
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
                if digits < 18 { mantissa = mantissa * 10 + UInt64(bytes[index] - 0x30); digits += 1; scale += 1 } else { exact = false }
                index += 1
            }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            exact = false
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 { index += 1 }
        }
        guard index > start + (negative ? 1 : 0) else { return nil }
        if exact && scale <= 22 {
            let value = Double(mantissa) / powersOfTen[scale]
            return negative ? -value : value
        }
        return Double(String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self))
    }

    private mutating func string() -> String? {
        index += 1
        let start = index
        var plain = true
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                if plain {
                    let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self)
                    index += 1
                    return text
                }
                break
            }
            if byte == UInt8(ascii: "\\") { plain = false; index += 2 } else { index += 1 }
        }
        // Escapes: decode again, one unit at a time.
        index = start
        var units: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                return String(decoding: units, as: UTF8.self)
            case UInt8(ascii: "\\"):
                guard index < bytes.count else { return nil }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "n"): units.append(0x0A)
                case UInt8(ascii: "t"): units.append(0x09)
                case UInt8(ascii: "r"): units.append(0x0D)
                case UInt8(ascii: "b"): units.append(0x08)
                case UInt8(ascii: "f"): units.append(0x0C)
                case UInt8(ascii: "u"):
                    guard var code = hex() else { return nil }
                    if (0xD800..<0xDC00).contains(code), index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"),
                       bytes[index + 1] == UInt8(ascii: "u") {
                        let next = index
                        index += 2
                        guard let low = hex() else { return nil }
                        if (0xDC00..<0xE000).contains(low) {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            // A high surrogate without its low half is a replacement character, and
                            // the escape after it is read on its own.
                            index = next
                        }
                    }
                    units.append(contentsOf: String(Character(Unicode.Scalar(code) ?? "\u{FFFD}")).utf8)
                default: units.append(escape)
                }
            default:
                units.append(byte)
            }
        }
        return nil
    }

    private mutating func hex() -> UInt32? {
        guard index + 4 <= bytes.count else { return nil }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            index += 1
            let digit: UInt8
            switch byte {
            case 0x30...0x39: digit = byte - 0x30
            case 0x41...0x46: digit = byte - 0x41 + 10
            case 0x61...0x66: digit = byte - 0x61 + 10
            default: return nil
            }
            value = value * 16 + UInt32(digit)
        }
        return value
    }
}

private let powersOfTen: [Double] = (0...22).map { pow(10, Double($0)) }

/// A catalog row's basis, nutrients and portions. Catalogs from version 3 on list their nutrient
/// keys in `catalog_meta` (`order`) and keep each row as `[basis, values in that order (null where
/// unknown, trailing ones left off), portions as [label, amount]?]`; earlier catalogs keep an object
/// `{basis, nutrients: {key: value}, portions: [{label, amount}]}`.
struct RowData {
    var basis: FoodBasis
    var nutrients: Nutrients
    var extras: [String: Double]
    var portions: [Portion]

    init?(_ json: JSONValue, order: [String]?) {
        var values: [String: Double] = [:]
        var portions: [Portion] = []
        let basisName: String?
        if let order {
            guard let row = json.array, row.count >= 2, let list = row[1].array else { return nil }
            basisName = row[0].string
            for (key, value) in zip(order, list) { if let number = value.number { values[key] = number } }
            if row.count > 2, let listed = row[2].array {
                for item in listed {
                    guard let pair = item.array, pair.count >= 2, let label = pair[0].string, let amount = pair[1].number else { continue }
                    portions.append(Portion(label: label, amount: amount))
                }
            }
        } else {
            guard let object = json.object, let nutrients = object["nutrients"]?.object else { return nil }
            basisName = object["basis"]?.string
            for (key, value) in nutrients { if let number = value.number { values[key] = number } }
            for item in object["portions"]?.array ?? [] {
                guard let fields = item.object, let label = fields["label"]?.string, let amount = fields["amount"]?.number else { continue }
                portions.append(Portion(label: label, amount: amount))
            }
        }
        guard let basis = basisName.flatMap(FoodBasis.init(rawValue:)) else { return nil }
        self.basis = basis
        self.portions = portions
        nutrients = Nutrients(kcal: values.removeValue(forKey: "calories") ?? 0, protein: values.removeValue(forKey: "protein") ?? 0,
                              carbs: values.removeValue(forKey: "carbs") ?? 0, fat: values.removeValue(forKey: "fat") ?? 0,
                              fiber: values.removeValue(forKey: "fiber"), sugar: values.removeValue(forKey: "sugar"),
                              saturatedFat: values.removeValue(forKey: "saturatedFat"), sodium: values.removeValue(forKey: "sodium"))
        extras = values
    }

    init?(data: UnsafeBufferPointer<UInt8>, order: [String]?) {
        guard let json = JSONValue.parse(data) else { return nil }
        self.init(json, order: order)
    }

    init?(data: String, order: [String]?) {
        guard let json = JSONValue.parse(data) else { return nil }
        self.init(json, order: order)
    }
}

/// A catalog barcode as its 14-digit key: v3 keeps a number, v2 the digits; USDA has none.
func barcodeKey(_ value: String?) -> String? {
    guard let value, !value.isEmpty, value.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
    return value.count >= 14 ? value : String(repeating: "0", count: 14 - value.count) + value
}
