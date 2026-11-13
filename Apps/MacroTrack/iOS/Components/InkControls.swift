import SwiftUI

// The design canvas's controls that `Stadig.swift` doesn't have yet: the round icon button
// (`.ibtn`), the solid button (`.btn`), the segmented range (`.seg`) and a tab's own title over the
// page (an eyebrow over a 32-point title, with its one button). Candidates for `Stadig.swift`, which
// both apps share; until then they're Stadig Macro's.

extension Color {
    /// Words on the accent: near-black green on leaf in dark mode, white on the deeper leaf in light.
    static let accentInk = Color(light: 0xFFFFFF, dark: 0x04291A)
}

/// A tab's title on the page, where the canvas has it rather than a navigation bar: what the screen
/// is about as an eyebrow, the title, and the screen's one button beside them.
struct PageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).eyebrow().lineLimit(1)
                Text(title).pageTitle().accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 4)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

extension View {
    /// The canvas's `.title`: 32 points, heavy and tight, growing with Dynamic Type to a cap.
    func pageTitle() -> some View { modifier(PageTitleStyle()) }

    /// A round 44-point button face on the card colour: the canvas's `.ibtn`.
    func circleIcon(fill: Color = Ink.surface) -> some View {
        font(.system(size: 17, weight: .regular))
            .foregroundStyle(Ink.text)
            .frame(width: 44, height: 44)
            .background(fill, in: .circle)
            .contentShape(.circle)
    }
}

private struct PageTitleStyle: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 32

    func body(content: Content) -> some View {
        let points = min(size, 48)
        content
            .font(.system(size: points, weight: .bold))
            .tracking(-points * 0.03)
            .foregroundStyle(Ink.text)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }
}

/// A round icon button: the canvas's `.ibtn`.
struct CircleIconButton: View {
    let symbol: String
    let label: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).circleIcon()
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// The canvas's `.btn`: a solid accent button, 52 points (44 small), or a quiet one on the raised
/// grey (`ghost`).
struct SolidButtonStyle: ButtonStyle {
    var small = false
    var ghost = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(small ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(ghost ? Ink.text : Color.accentInk)
            .padding(.horizontal, small ? 16 : 20)
            .frame(minHeight: small ? 44 : 52)
            .background(
                ghost ? Ink.raised : Color.accentColor,
                in: .rect(cornerRadius: small ? 14 : 16, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(.rect(cornerRadius: small ? 14 : 16, style: .continuous))
    }
}

extension ButtonStyle where Self == SolidButtonStyle {
    static var solid: SolidButtonStyle { SolidButtonStyle() }
    static var solidSmall: SolidButtonStyle { SolidButtonStyle(small: true) }
    static var ghost: SolidButtonStyle { SolidButtonStyle(small: true, ghost: true) }
}

/// The canvas's `.seg`: a few choices on the raised grey, the chosen one lifted onto the card colour.
struct InkSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(on ? Ink.text : Ink.text2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.surface)
                                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Ink.raised, in: .rect(cornerRadius: 13, style: .continuous))
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

/// Small uppercase labels along an axis or under a ruler: the canvas's `.scale`.
struct ScaleLabel: View {
    let text: String
    var highlighted = false

    init(_ text: String, highlighted: Bool = false) {
        self.text = text
        self.highlighted = highlighted
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(highlighted ? Ink.text : Ink.text3)
            .lineLimit(1)
    }
}

/// A card's title over its number or chart: the canvas's `.h3`, with an optional note at the right.
struct CardTitle: View {
    let title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let detail { Text(detail).font(.caption).foregroundStyle(Ink.text3).lineLimit(1) }
        }
    }
}

/// A row whose children share its width by weight (`layoutWeight`), as a CSS grid's `3fr 4fr 4fr`
/// does: the year's phases, each as long as it runs.
nonisolated struct WeightedRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let heights = zip(subviews, widths(width, subviews)).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width, subviews)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }

    private func widths(_ total: CGFloat, _ subviews: Subviews) -> [CGFloat] {
        let weights = subviews.map { $0[LayoutWeight.self] }
        let sum = max(weights.reduce(0, +), 0.0001)
        let room = max(0, total - spacing * CGFloat(max(0, subviews.count - 1)))
        return weights.map { room * $0 / sum }
    }
}

private nonisolated struct LayoutWeight: LayoutValueKey {
    static let defaultValue: Double = 1
}

extension View {
    /// This view's share of a `WeightedRow`.
    func layoutWeight(_ weight: Double) -> some View { layoutValue(key: LayoutWeight.self, value: weight) }
}
