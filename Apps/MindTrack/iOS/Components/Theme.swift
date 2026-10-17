import SwiftUI
import MindEngine
import SystemCore

// Liquid Glass belongs to the controls that float over content. Content sits on quiet grouped
// surfaces, as in Lift Track and Macro Track.

extension ShapeStyle where Self == Color {
    static var pageBackground: Color { Color(uiColor: .systemGroupedBackground) }
    static var cardBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var insetBackground: Color { Color(uiColor: .tertiarySystemGroupedBackground) }
}

extension Domain {
    /// One colour per domain, used everywhere it appears.
    var color: Color {
        switch self {
        case .japanese: .pink
        case .maths: .blue
        case .writing: .orange
        case .reading: .teal
        }
    }
}

extension View {
    /// A content card: grouped surface, continuous corners.
    func card(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.cardBackground, in: .rect(cornerRadius: radius))
    }

    /// The one action that matters on a screen.
    func primaryAction() -> some View { self.buttonStyle(.glassProminent).buttonBorderShape(.capsule) }

    func secondaryAction() -> some View { self.buttonStyle(.glass).buttonBorderShape(.capsule) }

    /// Readable line length on iPad.
    func readableWidth(_ width: CGFloat = 720) -> some View { frame(maxWidth: width).frame(maxWidth: .infinity) }
}

/// A small rounded label.
struct Pill: View {
    let text: String
    var symbol: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: .capsule)
    }
}

/// A section heading inside a scrolling page.
struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.top, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A domain's symbol in its colour.
struct DomainBadge: View {
    let domain: Domain
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: domain.symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(domain.color.gradient, in: .rect(cornerRadius: size * 0.3))
            .accessibilityLabel(domain.label)
    }
}

/// A plain-language "Why?" disclosure.
struct WhyDisclosure: View {
    let reasons: [String]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                    Text(reason).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Why?").font(.subheadline.weight(.semibold))
        }
    }
}

/// Discipline as a gauge with the 80–90% band shaded "in the zone". Past 90% earns nothing more.
struct DisciplineGauge: View {
    let score: DisciplineScore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Rectangle().fill(Color.green.opacity(0.25)).frame(width: width * 0.1).offset(x: width * 0.8)
                    if let rate = score.rate {
                        Capsule().fill(score.band == .below ? Color.orange : Color.green).frame(width: max(8, width * min(1, rate)))
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 12)
            HStack {
                Text(score.rate.map(Format.percent) ?? "—").font(.headline.monospacedDigit())
                Text(score.band?.label ?? "Nothing to score yet").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("Zone 80–90%").font(.caption).foregroundStyle(.secondary)
            }
            Text(score.note).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// An empty state with a single next step.
struct EmptyCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 24)
    }
}

extension Trajectory {
    var symbol: String {
        switch self {
        case .ahead, .onPace: "arrow.up.right"
        case .stalled: "arrow.right"
        case .regressing: "arrow.down.right"
        case .notEnoughData: "ellipsis"
        }
    }

    var color: Color {
        switch self {
        case .ahead, .onPace: .green
        case .stalled: .secondary
        case .regressing: .orange
        case .notEnoughData: .secondary
        }
    }
}

/// Numbers as people read them.
enum Format {
    static func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0))) }

    static func day(_ day: Day, style: Date.FormatStyle = .dateTime.weekday(.abbreviated).month(.abbreviated).day()) -> String {
        day.date().formatted(style)
    }

    static func minutes(_ value: Double) -> String {
        let whole = Int(value.rounded())
        return whole == 1 ? "1 min" : "\(whole) min"
    }

    static func seconds(_ value: Double) -> String { "\(Int(value.rounded())) s" }
}
