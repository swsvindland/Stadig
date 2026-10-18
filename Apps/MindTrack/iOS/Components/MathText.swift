import MindEngine
import SwiftUI

// Maths drawn natively from the small TeX subset the problems are written in: fractions, roots,
// powers and indices, integrals and limits, and the usual symbols. Text around it wraps; each piece
// of maths stays whole, aligned on the text baseline. MindEngine's MathSource parses it, once for
// drawing here and for VoiceOver.

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
                if !run.isEmpty {
                    out.append(.inline(run))
                    run = []
                }
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
        case .number, .function, .symbol, .command: .system(size: size, design: .serif)
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

    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
        cache: inout ()
    ) -> CGFloat? {
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
