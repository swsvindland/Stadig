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
    /// How it felt, in the few words the phone's buttons have room for: "3+ left".
    var shortDetail: String {
        switch self {
        case .green: "3+ left"
        case .orange: "0–2 left"
        case .red: "Fell short"
        }
    }

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

    /// The block's name for one exercise in it: "Main lift", "Accessory".
    var singular: String {
        switch self {
        case .main: "Main lift"
        case .accessory: "Accessory"
        default: label
        }
    }
}

extension View {
    /// A list or form on the ink ground, not the system's grouped grey. Its rows keep the system's
    /// grouped cells, the surface's colour near enough, in both appearances. Vision Pro keeps its glass.
    func inkList() -> some View {
        #if os(visionOS)
        self
        #else
        scrollContentBackground(.hidden).background(.pageBackground)
        #endif
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
                            Text(scale.isLarge ? rating.detail : rating.shortDetail)
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

extension String {
    /// "biggerAndStronger" as "BiggerAndStronger", to end an accessibility identifier built from a raw
    /// value ("onboarding.goalBiggerAndStronger").
    var identifierSuffix: String { prefix(1).uppercased() + dropFirst() }
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
