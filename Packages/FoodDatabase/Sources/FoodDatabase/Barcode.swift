import Foundation

/// Product barcodes as the catalogs key them: 14-digit GTINs, zero-padded.
public enum Barcode {
    /// What the scanner read the symbol as, when it says.
    public enum Symbology: String, Codable, Sendable {
        case ean8, ean13, upcA, upcE, itf14, other
    }

    /// Normalized 14-digit keys a scanned code could be stored under (UPC-E expanded).
    public static func keys(for code: String) -> [String] { keys(for: code, symbology: nil) }

    /// The 14-digit keys a code may be stored under, most likely first. An 8-digit code is EAN-8 or
    /// UPC-E (cans, gum), whose check digit is its UPC-A form's. Catalogs keep EAN-8 codes as
    /// printed, so the UPC-A form comes first only when the scanner read a UPC-E symbol.
    public static func keys(for code: String, symbology: Symbology?) -> [String] {
        let digits = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [8, 12, 13, 14].contains(digits.utf8.count), digits.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return [] }
        var keys = checkDigitValid(digits) ? [digits] : []
        if digits.utf8.count == 8, digits.utf8.first! <= UInt8(ascii: "1"), symbology != .ean8 {
            let upcA = expandUPCE(digits)
            if checkDigitValid(upcA) {
                if symbology == .upcE { keys.insert(upcA, at: 0) } else { keys.append(upcA) }
            }
        }
        return keys.map { String(repeating: "0", count: 14 - $0.count) + $0 }
    }

    /// Whether a code is a barcode some catalog could store: the right length and a check digit that fits.
    public static func isValid(_ code: String) -> Bool { !keys(for: code).isEmpty }

    /// GS1's mod-10 check: weights 3 and 1 from the digit before the check digit.
    static func checkDigitValid(_ code: String) -> Bool {
        let digits = code.utf8.map { Int($0) - 48 }
        guard let check = digits.last else { return false }
        var total = 0
        for (i, digit) in digits.dropLast().reversed().enumerated() { total += digit * (i % 2 == 1 ? 1 : 3) }
        return (10 - total % 10) % 10 == check
    }

    /// The 12-digit UPC-A form of an 8-digit UPC-E code (number system, 6 digits, check digit).
    static func expandUPCE(_ code: String) -> String {
        let d = code.map(String.init)
        let (system, a, b, c, x, e, last, check) = (d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7])
        let body: String
        switch last {
        case "0", "1", "2": body = "\(a)\(b)\(last)0000\(c)\(x)\(e)"
        case "3": body = "\(a)\(b)\(c)00000\(x)\(e)"
        case "4": body = "\(a)\(b)\(c)\(x)00000\(e)"
        default: body = "\(a)\(b)\(c)\(x)\(e)0000\(last)"
        }
        return system + body + check
    }
}
