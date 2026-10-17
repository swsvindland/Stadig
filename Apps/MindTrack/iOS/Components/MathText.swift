import SwiftUI

// Maths drawn natively from the small TeX subset the problems are written in: fractions, roots,
// powers and indices, integrals and limits, and the usual symbols. Text around it wraps; each piece
// of maths stays whole, aligned on the text baseline.

/// Text with inline maths between dollar signs.
struct MathText: View {
    let source: String
    var size: CGFloat = 19
    var weight: Font.Weight = .regular

    var body: some View {
        FlowLayout(spacing: size * 0.26, lineSpacing: size * 0.42) {
            ForEach(Array(MathSource.pieces(source).enumerated()), id: \.offset) { _, piece in
                switch piece {
                case .word(let word):
                    Text(word).font(.system(size: size, weight: weight))
                case .math(let nodes):
                    MathRow(nodes: nodes, size: size)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MathSource.spoken(source))
    }
}

indirect enum MathNode: Hashable {
    enum Style: Hashable { case variable, number, symbol, function, text }

    case atom(String, Style)
    case fraction([MathNode], [MathNode])
    case binom([MathNode], [MathNode])
    case root([MathNode])
    case scripts(base: [MathNode], sup: [MathNode]?, sub: [MathNode]?)
    /// ∫ with limits to its right; lim with what it approaches below.
    case bigOp(String, sup: [MathNode]?, sub: [MathNode]?)

    var isTall: Bool {
        switch self {
        case .fraction, .binom, .root: true
        case .bigOp(let op, let sup, let sub): op == "lim" ? sub != nil : (sup != nil || sub != nil)
        case .scripts(let base, _, _): base.contains(where: \.isTall)
        case .atom: false
        }
    }
}

enum MathSource {
    enum Piece { case word(String), math([MathNode]) }

    /// Splits text into words (which wrap) and maths (which doesn't).
    static func pieces(_ source: String) -> [Piece] {
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
        "{": "{", "}": "}",
    ]
    static let functions: Set<String> = ["sin", "cos", "tan", "ln", "log", "exp"]

    static func parse(_ text: String) -> [MathNode] {
        var parser = Parser(characters: Array(text))
        return parser.row()
    }

    struct Parser {
        let characters: [Character]
        var index = 0

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
                while !done, characters[index].isNumber || (characters[index] == "." && index + 1 < characters.count && characters[index + 1].isNumber) {
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
                    return [.atom(symbol, name == "pi" || name == "theta" ? .variable : .symbol)]
                }
                return [.atom(name, .text)]
            }
        }
    }

    /// Something VoiceOver can read: the maths with its symbols spelled out.
    static func spoken(_ source: String) -> String {
        var text = source.replacingOccurrences(of: "$", with: "")
        let words: [(String, String)] = [
            (#"\frac"#, " fraction "), (#"\sqrt"#, " square root of "), (#"\int"#, " integral "), (#"\lim"#, " limit "),
            ("^", " to the power "), ("_", " sub "), (#"\times"#, " times "), (#"\div"#, " divided by "), (#"\pi"#, " pi "),
            (#"\theta"#, " theta "), (#"\to"#, " approaches "), (#"\infty"#, " infinity "), (#"\le"#, " at most "), (#"\ge"#, " at least "),
            (#"\,"#, " "), ("{", " "), ("}", " "), ("\\", ""),
        ]
        for (from, to) in words { text = text.replacingOccurrences(of: from, with: to) }
        return text.split(separator: " ").joined(separator: " ")
    }
}

/// A row of maths: runs of plain symbols as one Text, tall pieces as their own views, all on one
/// baseline.
struct MathRow: View {
    let nodes: [MathNode]
    let size: CGFloat

    enum Chunk { case inline([MathNode]), tall(MathNode) }

    var chunks: [Chunk] {
        var out: [Chunk] = []
        var run: [MathNode] = []
        for node in nodes {
            if node.isTall {
                if !run.isEmpty { out.append(.inline(run)); run = [] }
                out.append(.tall(node))
            } else {
                run.append(node)
            }
        }
        if !run.isEmpty { out.append(.inline(run)) }
        return out
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                switch chunk {
                case .inline(let nodes): MathRow.text(nodes, size: size)
                case .tall(let node): TallMath(node: node, size: size)
                }
            }
        }
        .fixedSize()
    }

    static func font(_ style: MathNode.Style, _ size: CGFloat) -> Font {
        switch style {
        case .variable: .system(size: size, design: .serif).italic()
        case .number, .function, .symbol: .system(size: size, design: .serif)
        case .text: .system(size: size)
        }
    }

    /// Inline maths as one Text: scripts raised or lowered, fractions written a⁄b.
    static func text(_ nodes: [MathNode], size: CGFloat) -> Text {
        nodes.reduce(Text(verbatim: "")) { Text("\($0)\(text($1, size: size))") }
    }

    static func text(_ node: MathNode, size: CGFloat) -> Text {
        let symbol = { (s: String) in Text(verbatim: s).font(font(.symbol, size)) }
        switch node {
        case .atom(let s, let style):
            return Text(verbatim: s).font(font(style, size))
        case .scripts(let base, let sup, let sub):
            return Text("\(text(base, size: size))\(lowered(sub, size))\(raised(sup, size))")
        case .fraction(let n, let d):
            return Text("\(text(n, size: size))\(symbol("⁄"))\(text(d, size: size))")
        case .binom(let n, let r):
            return Text("\(symbol("C("))\(text(n, size: size))\(symbol(", "))\(text(r, size: size))\(symbol(")"))")
        case .root(let content):
            return Text("\(symbol("√("))\(text(content, size: size))\(symbol(")"))")
        case .bigOp(let op, let sup, let sub):
            let head = Text(verbatim: op).font(font(op == "lim" ? .function : .symbol, size))
            return Text("\(head)\(lowered(sub, size))\(raised(sup, size))")
        }
    }

    static func raised(_ nodes: [MathNode]?, _ size: CGFloat) -> Text {
        nodes.map { text($0, size: size * 0.68).baselineOffset(size * 0.42) } ?? Text(verbatim: "")
    }

    static func lowered(_ nodes: [MathNode]?, _ size: CGFloat) -> Text {
        nodes.map { text($0, size: size * 0.68).baselineOffset(-size * 0.2) } ?? Text(verbatim: "")
    }
}

/// Fractions, roots, binomials, integrals with limits and limits with their approach.
struct TallMath: View {
    let node: MathNode
    let size: CGFloat

    var body: some View {
        switch node {
        case .fraction(let n, let d):
            FractionLayout(size: size) {
                MathRow(nodes: n, size: size * 0.86)
                Rectangle().frame(height: max(1, size * 0.055))
                MathRow(nodes: d, size: size * 0.86)
            }
            .padding(.horizontal, size * 0.12)
        case .binom(let n, let r):
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("(").font(.system(size: size * 1.9, weight: .ultraLight)).baselineOffset(-size * 0.45)
                FractionLayout(size: size) {
                    MathRow(nodes: n, size: size * 0.86)
                    Color.clear.frame(height: size * 0.12)
                    MathRow(nodes: r, size: size * 0.86)
                }
                Text(")").font(.system(size: size * 1.9, weight: .ultraLight)).baselineOffset(-size * 0.45)
            }
        case .root(let content):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("√").font(.system(size: size * 1.12, design: .serif))
                MathRow(nodes: content, size: size)
                    .padding(.top, size * 0.12)
                    .overlay(alignment: .top) { Rectangle().frame(height: max(1, size * 0.055)) }
            }
        case .bigOp(let op, _, let sub) where op == "lim":
            VStack(spacing: 0) {
                Text("lim").font(.system(size: size, design: .serif))
                if let sub { MathRow(nodes: sub, size: size * 0.62) }
            }
            .padding(.trailing, size * 0.2)
        case .bigOp(let op, let sup, let sub):
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(op).font(.system(size: size * 1.6, design: .serif)).baselineOffset(-size * 0.3)
                VStack(alignment: .leading, spacing: size * 0.55) {
                    MathRow(nodes: sup ?? [], size: size * 0.62)
                    MathRow(nodes: sub ?? [], size: size * 0.62)
                }
                .alignmentGuide(.firstTextBaseline) { d in d.height * 0.66 }
            }
            .padding(.trailing, size * 0.1)
        case .scripts(let base, let sup, let sub):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                MathRow(nodes: base, size: size)
                VStack(alignment: .leading, spacing: 0) {
                    if let sup { MathRow(nodes: sup, size: size * 0.68) }
                    if let sub { MathRow(nodes: sub, size: size * 0.68) }
                }
                .alignmentGuide(.firstTextBaseline) { d in d.height * (sup != nil ? 1.4 : -0.2) }
            }
        case .atom:
            MathRow.text(node, size: size)
        }
    }
}

/// Numerator, bar, denominator, with the baseline set so the bar sits at the height of a minus sign.
struct FractionLayout: Layout {
    let size: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = sizes.enumerated().filter { $0.offset != 1 }.map(\.element.width).max() ?? 0
        return CGSize(width: width + size * 0.1, height: sizes.map(\.height).reduce(0, +) + gap * 2)
    }

    var gap: CGFloat { size * 0.1 }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let fitted = subview.sizeThatFits(.unspecified)
            if index == 1 {
                subview.place(at: CGPoint(x: bounds.minX, y: y + gap), proposal: ProposedViewSize(width: bounds.width, height: fitted.height))
                y += fitted.height + gap * 2
            } else {
                subview.place(at: CGPoint(x: bounds.midX - fitted.width / 2, y: y), proposal: .unspecified)
                y += fitted.height
            }
        }
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                           cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline, subviews.count == 3 else { return nil }
        let top = subviews[0].sizeThatFits(.unspecified).height
        let bar = subviews[1].sizeThatFits(.unspecified).height
        // The maths axis sits about a quarter of an em above the baseline.
        return bounds.minY + top + gap + bar / 2 + size * 0.28
    }
}

/// Lays views out in lines like words, each line aligned on its text baseline.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    struct Line {
        var items: [(index: Int, size: CGSize, baseline: CGFloat)] = []
        var width: CGFloat = 0
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
    }

    func lines(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = [Line()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let baseline = subview.dimensions(in: .unspecified)[VerticalAlignment.firstTextBaseline]
            let needed = lines[lines.count - 1].items.isEmpty ? size.width : lines[lines.count - 1].width + spacing + size.width
            if needed > width, !lines[lines.count - 1].items.isEmpty { lines.append(Line()) }
            var line = lines[lines.count - 1]
            line.width = line.items.isEmpty ? size.width : line.width + spacing + size.width
            line.items.append((index, size, baseline))
            line.ascent = max(line.ascent, baseline)
            line.descent = max(line.descent, size.height - baseline)
            lines[lines.count - 1] = line
        }
        return lines
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lines(subviews, width: width)
        let height = lines.map { $0.ascent + $0.descent }.reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: proposal.width ?? (lines.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(subviews, width: bounds.width) {
            var x = bounds.minX
            for item in line.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + line.ascent - item.baseline), proposal: .unspecified)
                x += item.size.width + spacing
            }
            y += line.ascent + line.descent + lineSpacing
        }
    }
}
