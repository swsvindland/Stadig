import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

// Stadig's look (Components/Stadig.swift): pages on the ink ground, paper in light mode, content on
// quiet surfaces, one accent for the one action that matters. Liquid Glass stays on the controls
// that float over content (bars, the session's dock). Vision Pro keeps its glass windows.

extension ShapeStyle where Self == Color {
    static var pageBackground: Color {
        #if os(visionOS)
        .groupedBackground
        #else
        Ink.ground
        #endif
    }

    static var cardBackground: Color {
        #if os(visionOS)
        .secondaryGroupedBackground
        #else
        Ink.surface
        #endif
    }

    static var insetBackground: Color {
        #if os(visionOS)
        .tertiaryGroupedBackground
        #else
        Ink.raised
        #endif
    }
}

extension Ink {
    /// Text and marks on the accent: white on the light theme's ultramarine, deep ink on the dark
    /// theme's lighter one (both past 4.5:1).
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0B1030)
}

extension SetRating {
    var color: Color {
        switch self {
        case .green: Ink.good
        case .orange: Ink.ok
        case .red: Ink.bad
        }
    }
}

// Colour only where it means something: a stat or a block is told by its name and symbol, in the
// app's one accent, not by a colour of its own.
extension StatKind {
    var color: Color { .accentColor }
}

extension SessionBlockKind {
    var color: Color { .accentColor }
}

extension View {
    /// A content card: a quiet surface on the ground, continuous corners.
    func card(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.cardBackground, in: .rect(cornerRadius: radius, style: .continuous))
    }

    func floatingGlass(in shape: some Shape = Capsule(), tint: Color? = nil, interactive: Bool = true) -> some View {
        adaptiveGlass(in: shape, tint: tint, interactive: interactive)
    }

    /// The one action that matters on a screen: filled with the accent. Vision Pro keeps its own
    /// prominent button over the glass.
    func primaryAction() -> some View {
        #if os(visionOS)
        prominentGlassButtonStyle().buttonBorderShape(.capsule)
        #else
        buttonStyle(InkButtonStyle(filled: true))
        #endif
    }

    func secondaryAction() -> some View {
        #if os(visionOS)
        glassButtonStyle().buttonBorderShape(.capsule)
        #else
        buttonStyle(InkButtonStyle(filled: false))
        #endif
    }

    /// A list or form on the ink ground, not the system's grouped grey. Its rows keep the system's
    /// grouped cells, the surface's colour near enough, in both appearances. Vision Pro keeps its glass.
    func inkList() -> some View {
        #if os(visionOS)
        self
        #else
        scrollContentBackground(.hidden).background(.pageBackground)
        #endif
    }

    /// Readable line length on iPad.
    func readableWidth(_ width: CGFloat = 720) -> some View { frame(maxWidth: width).frame(maxWidth: .infinity) }
}

/// The design's buttons: the accent filled for the one action, a raised fill for the rest. Its
/// height follows the control size, so a small one still fits in a row.
struct InkButtonStyle: ButtonStyle {
    var filled: Bool
    @Environment(\.controlSize) private var size
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let height: CGFloat =
            switch size {
            case .mini, .small: 34
            case .large, .extraLarge: 52
            default: 44
            }
        configuration.label
            .font(size == .large || size == .extraLarge ? .headline : .subheadline.weight(.semibold))
            .foregroundStyle(filled ? Ink.onAccent : Ink.text)
            .padding(.horizontal, size == .small || size == .mini ? 12 : 18)
            .frame(minHeight: height)
            .background(filled ? Color.accentColor : Ink.raised, in: .rect(cornerRadius: height >= 52 ? 16 : 12, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(.rect)
            .hoverHighlight()
    }
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

/// The three-tap rating. A dot in its colour, the word and how it felt: never colour alone. Just
/// right, the answer most sets should get, is the filled accent button between the other two.
struct RatingButtons: View {
    @Environment(\.sessionScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicType
    var compact = false
    /// Where it is, for UI tests: each button is "<screen>.ratingGreen" and so on.
    var screen = "logger"
    let action: (SetRating) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(SetRating.allCases.enumerated()), id: \.element) { index, rating in
                let filled = rating == .orange
                Button {
                    action(rating)
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            if !filled { Circle().fill(rating.color).frame(width: 8, height: 8) }
                            // Whole words: three across leave no room to break "Missed" in two.
                            Text(rating.label).font(scale.isLarge ? .title3.weight(.semibold) : .body.weight(.semibold))
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        // At the largest text sizes the word alone fits; VoiceOver still reads how it felt.
                        if !compact && !dynamicType.isAccessibilitySize {
                            Text(rating.detail)
                                .font(scale.isLarge ? .subheadline : .caption)
                                .foregroundStyle(filled ? Ink.onAccent.opacity(0.85) : Ink.text2)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(filled ? Ink.onAccent : Ink.text)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: compact ? 52 : scale.ratingHeight)
                    .background(filled ? Color.accentColor : Ink.raised, in: .rect(cornerRadius: 16, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .hoverHighlight()
                // Easy, Just right, Missed: 1, 2, 3, left to right as they're drawn.
                .keyboardShortcut(scale.shortcut(KeyEquivalent(Character("\(index + 1)"))))
                .accessibilityLabel("\(rating.label): \(rating.detail)")
                .accessibilityIdentifier("\(screen).rating\(rating.rawValue.identifierSuffix)")
            }
        }
    }
}

/// A logged set's rating: a dot in its colour, named for VoiceOver.
struct RatingMark: View {
    let rating: SetRating?

    var body: some View {
        if let rating {
            Circle()
                .fill(rating.color)
                .frame(width: 8, height: 8)
                .accessibilityElement()
                .accessibilityLabel(rating.label)
        }
    }
}

/// Discipline as a ruler with the 80% line marked: 80–90% is the zone, and past 90% earns nothing more.
struct DisciplineGauge: View {
    let score: DisciplineScore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Ruler(value: score.rate ?? 0, color: score.band == .below ? Ink.ok : .accentColor, marker: 0.8)
            HStack(alignment: .firstTextBaseline) {
                Text(score.rate.map(Format.percent) ?? "–").numeral(20)
                Text(score.band?.label ?? "Nothing planned yet").font(.subheadline).foregroundStyle(Ink.text2)
                Spacer()
                Text("Zone 80–90%").eyebrow()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Adherence \(score.rate.map(Format.percent) ?? "unknown"), \(score.band?.label ?? "")")
    }
}

/// A 0–100 score as a ruler ticked at each level (20, 40, 60, 80, 100). The one that needs work is
/// drawn in the warning colour.
struct ScoreBar: View {
    let score: Double
    var highlight = false

    var body: some View {
        Ruler(value: score / 100, color: highlight ? Ink.ok : .accentColor, height: 10, divisions: 5)
            .accessibilityHidden(true)
    }
}

/// An exercise's primary muscles in one line.
struct MuscleLine: View {
    let exercise: Exercise

    var body: some View {
        Text(exercise.primaryMuscles.map(\.label).joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// A plain-language "Why?" disclosure.
struct WhyDisclosure: View {
    let rationale: Rationale
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(rationale.reasons.enumerated()), id: \.offset) { _, reason in
                    Label(reason, systemImage: "circle.fill")
                        .labelStyle(BulletLabelStyle())
                        .font(.subheadline)
                }
                if let confidence = rationale.confidence {
                    Label(confidence, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
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

/// An empty state with a single next step.
struct EmptyCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title).foregroundStyle(Ink.text3)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(Ink.text2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 24)
    }
}

extension String {
    /// "biggerAndStronger" as "BiggerAndStronger", to end an accessibility identifier built from a raw
    /// value ("onboarding.goalBiggerAndStronger").
    var identifierSuffix: String { prefix(1).uppercased() + dropFirst() }
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
