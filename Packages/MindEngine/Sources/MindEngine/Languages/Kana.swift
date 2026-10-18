import Foundation

public enum Script: String, Codable, Sendable, CaseIterable {
    case hiragana, katakana

    public var label: String { self == .hiragana ? "Hiragana" : "Katakana" }
}

/// One kana and how it's said.
public struct Kana: Hashable, Sendable, Identifiable {
    public var kana: String
    public var romaji: String
    public var script: Script
    /// Teaching group: the basic rows, then voiced sounds, then combinations.
    public var group: Int

    public var id: String { kana }
    public var key: CardKey { .kana(kana) }
}

/// Hiragana first, then katakana; each as the basic rows (あ to ん), the voiced and half-voiced
/// sounds (が, ぱ), and the combinations (きゃ).
public enum KanaTable {
    static let basic: [(String, String)] = [
        ("あ", "a"), ("い", "i"), ("う", "u"), ("え", "e"), ("お", "o"),
        ("か", "ka"), ("き", "ki"), ("く", "ku"), ("け", "ke"), ("こ", "ko"),
        ("さ", "sa"), ("し", "shi"), ("す", "su"), ("せ", "se"), ("そ", "so"),
        ("た", "ta"), ("ち", "chi"), ("つ", "tsu"), ("て", "te"), ("と", "to"),
        ("な", "na"), ("に", "ni"), ("ぬ", "nu"), ("ね", "ne"), ("の", "no"),
        ("は", "ha"), ("ひ", "hi"), ("ふ", "fu"), ("へ", "he"), ("ほ", "ho"),
        ("ま", "ma"), ("み", "mi"), ("む", "mu"), ("め", "me"), ("も", "mo"),
        ("や", "ya"), ("ゆ", "yu"), ("よ", "yo"),
        ("ら", "ra"), ("り", "ri"), ("る", "ru"), ("れ", "re"), ("ろ", "ro"),
        ("わ", "wa"), ("を", "wo"), ("ん", "n"),
    ]
    static let voiced: [(String, String)] = [
        ("が", "ga"), ("ぎ", "gi"), ("ぐ", "gu"), ("げ", "ge"), ("ご", "go"),
        ("ざ", "za"), ("じ", "ji"), ("ず", "zu"), ("ぜ", "ze"), ("ぞ", "zo"),
        ("だ", "da"), ("ぢ", "ji"), ("づ", "zu"), ("で", "de"), ("ど", "do"),
        ("ば", "ba"), ("び", "bi"), ("ぶ", "bu"), ("べ", "be"), ("ぼ", "bo"),
        ("ぱ", "pa"), ("ぴ", "pi"), ("ぷ", "pu"), ("ぺ", "pe"), ("ぽ", "po"),
    ]
    static let combined: [(String, String)] = [
        ("きゃ", "kya"), ("きゅ", "kyu"), ("きょ", "kyo"), ("しゃ", "sha"), ("しゅ", "shu"), ("しょ", "sho"),
        ("ちゃ", "cha"), ("ちゅ", "chu"), ("ちょ", "cho"), ("にゃ", "nya"), ("にゅ", "nyu"), ("にょ", "nyo"),
        ("ひゃ", "hya"), ("ひゅ", "hyu"), ("ひょ", "hyo"), ("みゃ", "mya"), ("みゅ", "myu"), ("みょ", "myo"),
        ("りゃ", "rya"), ("りゅ", "ryu"), ("りょ", "ryo"), ("ぎゃ", "gya"), ("ぎゅ", "gyu"), ("ぎょ", "gyo"),
        ("じゃ", "ja"), ("じゅ", "ju"), ("じょ", "jo"), ("びゃ", "bya"), ("びゅ", "byu"), ("びょ", "byo"),
        ("ぴゃ", "pya"), ("ぴゅ", "pyu"), ("ぴょ", "pyo"),
    ]

    /// Every kana in teaching order.
    public static let all: [Kana] = {
        var out: [Kana] = []
        for script in Script.allCases {
            for (group, rows) in [basic, voiced, combined].enumerated() {
                for (kana, romaji) in rows {
                    out.append(Kana(kana: script == .hiragana ? kana : katakana(kana), romaji: romaji, script: script, group: group))
                }
            }
        }
        return out
    }()

    public static let byKana: [String: Kana] = Dictionary(all.map { ($0.kana, $0) }, uniquingKeysWith: { a, _ in a })

    public static func kana(_ script: Script) -> [Kana] { all.filter { $0.script == script } }

    /// Hiragana to katakana: the blocks are 0x60 apart.
    public static func katakana(_ hiragana: String) -> String {
        String(
            String.UnicodeScalarView(
                hiragana.unicodeScalars.map { scalar in
                    (0x3041...0x3096).contains(scalar.value) ? Unicode.Scalar(scalar.value + 0x60)! : scalar
                }))
    }

    /// Pairs people mix up, offered as the wrong answers first.
    static let lookalikes: [[String]] = [
        ["さ", "ち", "き"], ["ぬ", "め", "の"], ["ね", "れ", "わ"], ["る", "ろ"], ["は", "ほ", "け"], ["い", "り", "こ"],
        ["シ", "ツ", "ン", "ソ"], ["ク", "ケ", "タ"], ["ユ", "コ", "ヨ"], ["ワ", "ウ", "フ"], ["チ", "テ", "ナ"], ["ノ", "メ", "ヌ"],
    ]

    public static func lookalikes(of kana: String) -> [String] {
        lookalikes.first { $0.contains(kana) }?.filter { $0 != kana } ?? []
    }

    /// Kana in romaji ("コーヒー" is "koohii"), or nil if it isn't all kana.
    public static func romaji(_ text: String) -> String? {
        let segments = Scaffolds.kana(text, Scaffolds.Context(cards: [:], frontier: 0, readsKana: false))
        guard segments.allSatisfy({ $0.help != nil }) else { return nil }
        return segments.compactMap(\.help).joined()
    }

    public static func containsKatakana(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x30A1...0x30FA).contains($0.value) }
    }
}
