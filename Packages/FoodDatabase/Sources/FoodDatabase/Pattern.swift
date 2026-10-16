import Foundation

/// A compiled regular expression with JavaScript-like helpers, for the few places text is read by
/// pattern (portion labels, nutrition panels). Immutable, so shareable.
struct Pattern: @unchecked Sendable {
    private let regex: NSRegularExpression

    init(_ pattern: String, ignoringCase: Bool = false) {
        // Every pattern is a literal in this module; a bad one is a programming error.
        regex = try! NSRegularExpression(pattern: pattern, options: ignoringCase ? [.caseInsensitive] : [])
    }

    /// A match: the whole text and each group (nil when a group took no part), and where it was.
    struct Match {
        var groups: [String?]
        var range: Range<String.Index>
        var whole: String { groups[0] ?? "" }
        subscript(_ group: Int) -> String? { group < groups.count ? groups[group] : nil }
    }

    func test(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    func first(in text: String) -> Match? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).map { read($0, text) }
    }

    func all(in text: String) -> [Match] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { read($0, text) }
    }

    /// Every match replaced with a template ("$1"), as JavaScript's `replace` with the `g` flag.
    func replacing(in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// Every match replaced with what `replacement` makes of it.
    func replacing(in text: String, _ replacement: (Match) -> String) -> String {
        var result = ""
        var rest = text.startIndex
        for match in all(in: text) {
            result += text[rest..<match.range.lowerBound]
            result += replacement(match)
            rest = match.range.upperBound
        }
        return result + text[rest...]
    }

    private func read(_ result: NSTextCheckingResult, _ text: String) -> Match {
        let groups = (0..<result.numberOfRanges).map { i in Range(result.range(at: i), in: text).map { String(text[$0]) } }
        return Match(groups: groups, range: Range(result.range, in: text) ?? text.startIndex..<text.startIndex)
    }
}
