import SwiftUI
import NutritionEngine
import SystemCore

// Liquid Glass belongs to the controls that float over content (the quick-log bar, the toast).
// Content sits on quiet grouped surfaces so the glass has something to refract.

extension ShapeStyle where Self == Color {
    static var pageBackground: Color { Color(uiColor: .systemGroupedBackground) }
    static var cardBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var insetBackground: Color { Color(uiColor: .tertiarySystemGroupedBackground) }
}

/// One colour per macro, used everywhere the macro appears.
enum Macro: CaseIterable {
    case kcal, protein, carbs, fat

    var color: Color {
        switch self {
        case .kcal: .accentColor
        case .protein: .pink
        case .carbs: .blue
        case .fat: .orange
        }
    }

    var label: String {
        switch self {
        case .kcal: "Calories"
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
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

    func floatingGlass(in shape: some Shape = Capsule(), tint: Color? = nil, interactive: Bool = true) -> some View {
        self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
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

/// A ring that fills toward a target; past the target it keeps its colour, never alarming red.
struct ProgressRing: View {
    let value: Double
    let target: Double?
    var color: Color = .accentColor
    var lineWidth: CGFloat = 14

    var fraction: Double { target.map { $0 > 0 ? value / $0 : 0 } ?? 0 }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, fraction))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if fraction > 1 {
                Circle()
                    .trim(from: 0, to: min(1, fraction - 1))
                    .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: lineWidth * 0.45, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.snappy, value: fraction)
        .accessibilityHidden(true)
    }
}

/// One macro as a labelled bar: eaten of target.
struct MacroBar: View {
    let macro: Macro
    let eaten: Double
    let target: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(macro.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if let target {
                    Text(remaining(target)).font(.caption.weight(.semibold).monospacedDigit())
                } else {
                    Text(Format.grams(eaten)).font(.caption.weight(.semibold).monospacedDigit())
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(macro.color.opacity(0.16))
                    if let target, target > 0 {
                        Capsule().fill(macro.color.gradient).frame(width: max(6, proxy.size.width * min(1, eaten / target)))
                    }
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(macro.label): \(Format.grams(eaten))\(target.map { " of \(Format.grams($0))" } ?? "")")
    }

    func remaining(_ target: Double) -> String {
        let left = target - eaten
        return left >= 0 ? "\(Format.grams(left)) left" : "\(Format.grams(-left)) over"
    }
}

/// A plain-language "Why?" disclosure.
struct WhyDisclosure: View {
    let reasons: [String]
    var confidence: String?
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                    Label(reason, systemImage: "circle.fill").labelStyle(BulletLabelStyle()).font(.subheadline)
                }
                if let confidence {
                    Label(confidence, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Why?").font(.subheadline.weight(.semibold))
        }
    }
}

struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(.secondary).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            configuration.title
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

/// "Logged Oats · 300 kcal   Undo", floating above the tab bar for a few seconds.
struct ToastView: View {
    let toast: Toast
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(toast.message).font(.subheadline.weight(.medium)).lineLimit(2)
            Spacer(minLength: 4)
            if toast.canUndo {
                Button("Undo", action: undo).font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .floatingGlass(in: Capsule())
        .padding(.horizontal)
    }
}
