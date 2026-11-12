import NutritionEngine
import SwiftUI
import SystemCore

// Liquid Glass belongs to the controls that float over content (the composer, the toast). Content
// sits on Stadig's ink ground (paper in light mode, Stadig.swift), so the glass has something to
// refract. Vision Pro keeps its window's glass as the page.

extension ShapeStyle where Self == Color {
    static var pageBackground: Color {
        #if os(visionOS)
        return .groupedBackground
        #else
        return Ink.ground
        #endif
    }
    /// On the Mac the window's and the controls' backgrounds are nearly the same, so a card is a
    /// faint fill over the page instead.
    static var cardBackground: Color {
        #if os(macOS)
        return Color(nsColor: .quaternarySystemFill)
        #elseif os(visionOS)
        return .secondaryGroupedBackground
        #else
        return Ink.surface
        #endif
    }
    static var insetBackground: Color {
        #if os(visionOS)
        return .tertiaryGroupedBackground
        #else
        return Ink.raised
        #endif
    }
}

/// One colour per macro, used everywhere the macro appears.
enum Macro: CaseIterable {
    case kcal, protein, carbs, fat

    var color: Color {
        switch self {
        case .kcal: .accentColor
        case .protein: Ink.protein
        case .carbs: Ink.carbs
        case .fat: Ink.fat
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
        adaptiveGlass(in: shape, tint: tint, interactive: interactive)
    }

    /// The one action that matters on a screen.
    func primaryAction() -> some View { prominentGlassButtonStyle().buttonBorderShape(.capsule) }

    func secondaryAction() -> some View { glassButtonStyle().buttonBorderShape(.capsule) }

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
        #if os(visionOS)
        // On glass a tint's own text over a faint wash of it can't be read: the tint fills the
        // capsule instead, under white text.
        .foregroundStyle(color == .secondary ? color : .white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color == .secondary ? color.opacity(0.14) : color.opacity(0.7), in: .capsule)
        #else
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: .capsule)
        #endif
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

/// One macro as a labelled thin ruler: eaten of target.
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
            Ruler.thin(target.map { $0 > 0 ? eaten / $0 : 0 } ?? 0, color: macro.color)
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
            configuration.icon.font(.system(size: 5)).foregroundStyle(.secondary).alignmentGuide(.firstTextBaseline) {
                $0[VerticalAlignment.center] + 4
            }
            configuration.title
        }
    }
}

/// Discipline as a ruler, ticked every tenth so the 80–90% zone reads off it, with the zone's start
/// marked. Past 90% earns nothing more.
struct DisciplineGauge: View {
    let score: DisciplineScore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Ruler(value: score.rate ?? 0, color: score.band == .below ? Ink.ok : Ink.good, height: 14, marker: 0.8)
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
            Image(systemName: toast.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.failed ? Color.orange : .green)
            Text(toast.message).font(.subheadline.weight(.medium)).lineLimit(2)
                .accessibilityIdentifier("toast.message")
            Spacer(minLength: 4)
            if toast.canUndo {
                Button("Undo", action: undo).font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("toast.undo")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .floatingGlass(in: Capsule())
        .padding(.horizontal)
    }
}

extension View {
    /// A choice's tint: the accent when picked, grey otherwise. On Vision Pro's glass a grey tint is
    /// white on white, so there an unpicked choice keeps the system's own glass.
    func choiceTint(_ picked: Bool) -> some View {
        #if os(visionOS)
        tint(picked ? Color.accentColor : nil)
        #else
        tint(picked ? Color.accentColor : .secondary)
        #endif
    }
}
