import Foundation

// The small TeX subset the problems are written in, parsed once for drawing and for VoiceOver:
// fractions, roots, powers and indices, integrals and limits, and the usual symbols. Here rather
// than beside the view so the spoken form can be checked against every string the curriculum
// writes.

/// A piece of parsed maths.
public indirect enum MathNode: Hashable, Sendable {
    /// `command`: a symbol written as a TeX command, by its name, so it's read aloud as a word
    /// (`\mid` as "given", where a plain `|` is a bar).
    public enum Style: Hashable, Sendable { case variable, number, symbol, command(String), function, text }

    case atom(String, Style)
    case fraction([MathNode], [MathNode])
    case binom([MathNode], [MathNode])
    case root([MathNode])
    case scripts(base: [MathNode], sup: [MathNode]?, sub: [MathNode]?)
    /// ∫ with limits to its right; lim with what it approaches below.
    case bigOp(String, sup: [MathNode]?, sub: [MathNode]?)

    /// Drawn on more than one line: a fraction, a binomial, a root, or a big operator with limits.
    public var isTall: Bool {
        switch self {
        case .fraction, .binom, .root: true
        case .bigOp(let op, let sup, let sub): op == "lim" ? sub != nil : (sup != nil || sub != nil)
        case .scripts(let base, _, _): base.contains(where: \.isTall)
        case .atom: false
        }
    }
}

/// Text with inline maths between dollar signs: "Solve $3x + 5 = 20$".
public enum MathSource {
    public enum Piece: Hashable, Sendable { case word(String), math([MathNode]) }

    /// Splits text into words (which wrap) and maths (which doesn't).
    public static func pieces(_ source: String) -> [Piece] {
        var out: [Piece] = []
        for (index, segment) in source.components(separatedBy: "$").enumerated() {
            if index % 2 == 1 {
                if !segment.isEmpty { out.append(.math(parse(segment))) }
            } else {
                var words = segment.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
                // Punctuation straight after maths belongs to it: "$x = 4$." keeps its full stop on the same line.
                if index > 0, let first = words.first, !first.isEmpty, case .math(let nodes)? = out.last {
                    out[out.count - 1] = .math(nodes + [.atom(first, .text)])
                    words.removeFirst()
                }
                out += words.filter { !$0.isEmpty }.map(Piece.word)
            }
        }
        return out
    }

    static let symbols: [String: String] = [
        "times": "×", "div": "÷", "cdot": "·", "pm": "±", "le": "≤", "ge": "≥", "neq": "≠", "approx": "≈", "to": "→",
        "infty": "∞", "pi": "π", "theta": "θ", "circ": "°", "ldots": "…", "%": "%", ",": "\u{2009}", " ": " ", "quad": "\u{2003}",
        "{": "{", "}": "}", "cup": "∪", "cap": "∩", "mid": "|", "sum": "∑", "in": "∈", "neg": "¬", "land": "∧", "lor": "∨",
    ]
    static let functions: Set<String> = ["sin", "cos", "tan", "ln", "log", "exp"]

    /// One stretch of maths (without its dollar signs).
    public static func parse(_ text: String) -> [MathNode] {
        var parser = Parser(characters: Array(text))
        return parser.row()
    }

    /// Commands in the text that this subset doesn't know, which are drawn as their bare names.
    static func unknownCommands(_ source: String) -> [String] {
        source.components(separatedBy: "$").enumerated().filter { $0.offset % 2 == 1 }.flatMap { _, segment in
            var parser = Parser(characters: Array(segment))
            _ = parser.row()
            return parser.unknown
        }
    }

    struct Parser {
        let characters: [Character]
        var index = 0
        /// Commands met that aren't in the subset.
        var unknown: [String] = []

        var done: Bool { index >= characters.count }

        mutating func row(untilBrace: Bool = false) -> [MathNode] {
            var nodes: [MathNode] = []
            while !done {
                let c = characters[index]
                if c == "}" {
                    index += 1
                    if untilBrace { return nodes }
                    continue
                }
                if c == "^" || c == "_" {
                    index += 1
                    let argument = self.argument()
                    attach(argument, superscript: c == "^", to: &nodes)
                    continue
                }
                nodes += item()
            }
            return nodes
        }

        /// One script or command argument: a {group} or a single item.
        mutating func argument() -> [MathNode] {
            guard !done else { return [] }
            if characters[index] == "{" {
                index += 1
                return row(untilBrace: true)
            }
            return item()
        }

        mutating func attach(_ script: [MathNode], superscript: Bool, to nodes: inout [MathNode]) {
            let last = nodes.popLast() ?? .atom("", .text)
            switch last {
            case .bigOp(let op, let sup, let sub):
                nodes.append(.bigOp(op, sup: superscript ? script : sup, sub: superscript ? sub : script))
            case .scripts(let base, let sup, let sub) where (superscript ? sup : sub) == nil:
                nodes.append(.scripts(base: base, sup: superscript ? script : sup, sub: superscript ? sub : script))
            default:
                nodes.append(.scripts(base: [last], sup: superscript ? script : nil, sub: superscript ? nil : script))
            }
        }

        mutating func item() -> [MathNode] {
            let c = characters[index]
            if c == "{" {
                index += 1
                return row(untilBrace: true)
            }
            if c == "\\" { return command() }
            index += 1
            if c.isNumber || c == "." {
                var digits = String(c)
                while !done,
                    characters[index].isNumber || (characters[index] == "." && index + 1 < characters.count && characters[index + 1].isNumber)
                {
                    digits.append(characters[index])
                    index += 1
                }
                return [.atom(digits, .number)]
            }
            if c.isLetter { return [.atom(String(c), .variable)] }
            if c == "-" { return [.atom("−", .symbol)] }
            if c == "'" { return [.atom("′", .symbol)] }
            return [.atom(String(c), c == " " ? .text : .symbol)]
        }

        mutating func command() -> [MathNode] {
            index += 1
            guard !done else { return [] }
            var name = ""
            if characters[index].isLetter {
                while !done, characters[index].isLetter {
                    name.append(characters[index])
                    index += 1
                }
            } else {
                name = String(characters[index])
                index += 1
            }
            switch name {
            case "frac": return [.fraction(argument(), argument())]
            case "binom": return [.binom(argument(), argument())]
            case "sqrt": return [.root(argument())]
            case "int": return [.bigOp("∫", sup: nil, sub: nil)]
            case "lim": return [.bigOp("lim", sup: nil, sub: nil)]
            case "left", "right": return []
            case "bar": return argument() + [.atom("\u{0304}", .command("bar"))]
            case "text":
                guard !done, characters[index] == "{" else { return [] }
                index += 1
                var words = ""
                while !done, characters[index] != "}" {
                    words.append(characters[index])
                    index += 1
                }
                index += 1
                return [.atom(words, .text)]
            default:
                if MathSource.functions.contains(name) { return [.atom(name, .function)] }
                if let symbol = MathSource.symbols[name] {
                    return [.atom(symbol, name == "pi" || name == "theta" ? .variable : .command(name))]
                }
                unknown.append(name)
                return [.atom(name, .text)]
            }
        }
    }

    // MARK: Spoken

    /// Something VoiceOver can read: the maths in words, from the same parse that draws it, so each
    /// command is read whole (`\left` isn't "at most ft") and fractions, powers and roots say what
    /// they are.
    public static func spoken(_ source: String) -> String {
        let text = pieces(source).map { piece in
            switch piece {
            case .word(let word): word
            case .math(let nodes): spoken(nodes)
            }
        }.joined(separator: " ")
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: #"\s+([.,;:?!)])"#, with: "$1", options: .regularExpression)
    }

    /// Commands read as words. Any other symbol command is read as it's drawn.
    static let commandWords: [String: String] = [
        "times": "times", "div": "divided by", "cdot": "times", "pm": "plus or minus", "le": "at most", "ge": "at least",
        "neq": "is not equal to", "approx": "approximately", "to": "approaches", "infty": "infinity", "circ": "degrees",
        "ldots": "and so on", "cup": "union", "cap": "intersection", "mid": "given", "sum": "the sum of", "in": "in", "neg": "not",
        "land": "and", "lor": "or", "{": "", "}": "", "bar": "",
    ]
    /// Characters VoiceOver would otherwise read oddly or not at all.
    static let characterWords: [String: String] = ["π": "pi", "θ": "theta", "−": "minus", "′": "prime"]

    /// Atoms run together as written ("8,400", "2x"); words for symbols and structure get spaces.
    public static func spoken(_ nodes: [MathNode]) -> String {
        var out = ""
        for (index, node) in nodes.enumerated() {
            // \bar puts its macron after what it covers: x̄ is the mean of x.
            if index + 1 < nodes.count, case .atom(_, .command("bar")) = nodes[index + 1] { out += " mean of " }
            // A thin space between digits groups them ("86\,000") and reads as nothing, so the
            // number is read whole. Anywhere else ("x\,dx") it's a space.
            if case .atom(_, .command(",")) = node, case .atom(_, .number)? = nodes[safe: index - 1],
                case .atom(_, .number)? = nodes[safe: index + 1]
            {
                continue
            }
            out += spoken(node)
        }
        return out
    }

    static func spoken(_ node: MathNode) -> String {
        switch node {
        case .atom(let text, .command(let name)):
            return " \(commandWords[name] ?? text) "
        case .atom(let text, _):
            return characterWords[text].map { " \($0) " } ?? text
        case .fraction(let n, let d):
            return " \(spoken(n)) over \(spoken(d)) "
        case .binom(let n, let r):
            return " \(spoken(n)) choose \(spoken(r)) "
        case .root(let content):
            return " square root of \(spoken(content)) "
        case .scripts(let base, let sup, let sub):
            return spoken(base) + (sub.map { " sub \(spoken($0)) " } ?? "") + (sup.map { " to the power \(spoken($0)) " } ?? "")
        case .bigOp(let op, _, let sub) where op == "lim":
            return " limit " + (sub.map { " as \(spoken($0)) " } ?? "")
        case .bigOp(_, let sup, let sub):
            return " integral " + (sub.map { " from \(spoken($0)) " } ?? "") + (sup.map { " to \(spoken($0)) " } ?? "")
        }
    }
}
