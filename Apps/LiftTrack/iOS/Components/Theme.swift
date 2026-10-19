import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

// Liquid Glass belongs to the controls that float over content (bars, the rest timer, the set
// logger). Content sits on quiet grouped surfaces so the glass has something to refract.

extension ShapeStyle where Self == Color {
    static var pageBackground: Color { .groupedBackground }

    /// On the Mac a card is a fill over the window, as a grouped form's sections are: a control
    /// background would vanish into the window in dark mode.
    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .quaternarySystemFill)
        #else
        .secondaryGroupedBackground
        #endif
    }

    static var insetBackground: Color {
        #if os(macOS)
        Color(nsColor: .quaternarySystemFill)
        #else
        .tertiaryGroupedBackground
        #endif
    }
}

extension SetRating {
    var color: Color {
        switch self {
        case .green: .green
        case .orange: .orange
        case .red: .red
        }
    }
}

extension StatKind {
    var color: Color {
        switch self {
        case .strength: .orange
        case .physique: .pink
        case .endurance: .red
        case .vitality: .indigo
        case .agility: .teal
        case .discipline: .blue
        case .intelligence: .purple
        case .wisdom: .brown
        }
    }
}

extension SessionBlockKind {
    var color: Color {
        switch self {
        case .warmup: .yellow
        case .limiter: .teal
        case .main: .orange
        case .accessory: .indigo
        case .conditioning: .red
        case .cooldown: .mint
        case .recovery: .pink
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

/// The three-tap rating. Colour, symbol and words together: never colour alone.
struct RatingButtons: View {
    @Environment(\.sessionScale) private var scale
    var compact = false
    /// Where it is, for UI tests: each button is "<screen>.ratingGreen" and so on.
    var screen = "logger"
    let action: (SetRating) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(SetRating.allCases.enumerated()), id: \.element) { index, rating in
                Button {
                    action(rating)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: rating.symbol).font(compact ? .title3 : .title2)
                        Text(rating.label).font(.subheadline.weight(.semibold))
                        if !compact {
                            Text(rating.detail).font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(2).multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: compact ? 56 : scale.ratingHeight)
                    .background(rating.color.gradient, in: .rect(cornerRadius: 18))
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

/// A logged set's rating as a small symbol in its colour.
struct RatingMark: View {
    let rating: SetRating?

    var body: some View {
        if let rating {
            Image(systemName: rating.symbol)
                .foregroundStyle(rating.color)
                .accessibilityLabel(rating.label)
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
                    Rectangle()
                        .fill(Color.green.opacity(0.25))
                        .frame(width: width * 0.1)
                        .offset(x: width * 0.8)
                    if let rate = score.rate {
                        Capsule()
                            .fill(score.band == .below ? Color.orange : Color.green)
                            .frame(width: max(8, width * min(1, rate)))
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 12)
            HStack {
                Text(score.rate.map(Format.percent) ?? "—").font(.headline.monospacedDigit())
                Text(score.band?.label ?? "Nothing planned yet").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("Zone 80–90%").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Adherence \(score.rate.map(Format.percent) ?? "unknown"), \(score.band?.label ?? "")")
    }
}

/// A 0–100+ score as a bar with level marks at 20, 40, 60, 80 and 100.
struct ScoreBar: View {
    let score: Double
    var color: Color = .orange
    var highlight = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.12))
                Capsule().fill(color.opacity(highlight ? 1 : 0.75)).frame(width: max(6, width * min(1, score / 120)))
                ForEach([20.0, 40, 60, 80, 100], id: \.self) { mark in
                    Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1).offset(x: width * mark / 120)
                }
            }
            .clipShape(.capsule)
        }
        .frame(height: 10)
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
            Image(systemName: symbol).font(.title).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
