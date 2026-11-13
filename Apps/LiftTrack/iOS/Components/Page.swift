import LiftEngine
import SwiftUI
import SystemCore

// The phone's own page furniture, as the design draws it (docs/design.md): no navigation bar, but an
// eyebrow over a large title with round buttons beside it, and lists as tight cards of rows. Stadig
// Lift's alone; `Components/Stadig.swift` holds what both apps share.

/// A screen's title as the design sets it: 32 points, bold and tightly tracked, growing with the text size.
struct PageTitle: View {
    let text: String
    var size: CGFloat = 32
    @ScaledMetric(relativeTo: .largeTitle) private var scaled: CGFloat = 32

    init(_ text: String, size: CGFloat = 32) {
        self.text = text
        self.size = size
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        Text(text)
            .font(.system(size: scaled, weight: .bold))
            .tracking(-scaled * 0.035)
            .foregroundStyle(Ink.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A tab's header: an eyebrow over the title, and its round buttons on the right.
struct PageHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    @ViewBuilder let trailing: Trailing

    init(eyebrow: String?, title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.eyebrow = eyebrow
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow { Text(eyebrow).eyebrow().lineLimit(1) }
                PageTitle(title)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

/// A pushed screen's header: a round back button, then the eyebrow over the title. The page hides the
/// navigation bar (`pageWithoutBar()`), so this is its way back.
struct BackHeader<Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss
    let eyebrow: String?
    let title: String?
    @ViewBuilder let trailing: Trailing

    init(eyebrow: String? = nil, title: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.eyebrow = eyebrow
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                dismiss()
            } label: {
                CircleIcon(symbol: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("page.back")
            if title != nil || eyebrow != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let eyebrow { Text(eyebrow).eyebrow().lineLimit(1) }
                    if let title { PageTitle(title) }
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 8)
    }
}

extension View {
    /// A pushed phone screen that draws its own header (`BackHeader`): the navigation bar's hidden, and
    /// the tab bar with it, as the design's detail screens have none. Wide windows keep their bar and title.
    func pageWithoutBar(title: String, wide: Bool) -> some View {
        navigationTitle(title)
            .inlineTitle()
            #if os(iOS)
        .toolbarVisibility(wide ? .automatic : .hidden, for: .navigationBar)
        .toolbarVisibility(wide ? .automatic : .hidden, for: .tabBar)
            #endif
    }

    /// The design's tight card of rows: 18-point corners, 14 points in from the sides.
    func tightCard() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
    }
}

/// Rows in a tight card with hairlines between, under an optional eyebrow inside the card.
struct RowCard<Content: View>: View {
    var title: String?
    var detail: String?
    var minHeight: CGFloat = 52
    @ViewBuilder let content: Content

    var body: some View {
        Group(subviews: content) { rows in
            // Nothing to show (no steps without Health, nothing outside the gym): no empty card.
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    if let title {
                        HStack(alignment: .firstTextBaseline) {
                            Text(title).eyebrow().accessibilityAddTraits(.isHeader)
                            Spacer()
                            if let detail { Text(detail).font(.caption).foregroundStyle(Ink.text3) }
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Rectangle().fill(Ink.hairline).frame(height: 1) }
                        row.padding(.vertical, 8).frame(minHeight: minHeight)
                    }
                }
                .tightCard()
            }
        }
    }
}

/// A row that opens something: a title, a caption under it, and a chevron.
struct LinkRowLabel: View {
    let title: String
    var caption: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                if let caption, !caption.isEmpty {
                    Text(caption).font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if let trailing { Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(Ink.text2) }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Ink.text3)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A score's trend as the design's small chip beside a hero numeral: "Rising" in green with an arrow up.
/// Nothing keeps a score's history yet, so it's a word, not "+2 this month" (docs/decisions.md).
struct TrendChip: View {
    let trend: TrendWord

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = trend.symbol { Image(systemName: symbol).font(.caption2.weight(.bold)) }
            Text(trend.text.prefix(1).uppercased() + trend.text.dropFirst())
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(trend.color)
        .padding(.horizontal, 11)
        .frame(minHeight: 28)
        .background(trend.color.opacity(0.14), in: .capsule)
        .lineLimit(1)
        .fixedSize()
    }
}
