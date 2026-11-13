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

extension Ink {
    /// Words on the accent: near-black green on leaf in dark mode, white on the deeper leaf in light.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x04291A)
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

/// "Logged Oats · 300 kcal   Undo", floating above the tab bar for a few seconds.
struct ToastView: View {
    let toast: Toast
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.failed ? Ink.ok : Ink.good)
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
