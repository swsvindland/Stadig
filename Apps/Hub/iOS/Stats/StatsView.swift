import HubEngine
import SwiftUI
import SystemCore

/// The eight stats from every app, side by side. There's no overall level, and nothing here is
/// logged: each app owns its own numbers.
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var open: StatKind?

    private var subtitle: String { HubText.updated(model.statsUpdated, today: model.today) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if Platform.isVision {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if sizeClass == .regular {
                        CardColumns {
                            ForEach(model.stats) { line in
                                row(line).card(padding: 12, radius: 18)
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(model.stats) { line in
                                row(line)
                                if line.id != model.stats.last?.id { Divider() }
                            }
                        }
                        .card(padding: 12, radius: 18)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .pageWidth(sizeClass)
            }
            .background(.pageBackground)
            .navigationTitle("Stats")
            .navigationSubtitleIfAvailable(subtitle)
        }
    }

    private func row(_ line: StatLine) -> some View {
        Button {
            open = open == line.stat ? nil : line.stat
        } label: {
            StatRow(line: line, isOpen: open == line.stat)
        }
        .buttonStyle(.plain)
        .disabled(!line.isKnown)
        .accessibilityIdentifier("stats.\(line.stat.rawValue)")
    }
}

/// A stat: its score and trend, and on a tap where it came from.
struct StatRow: View {
    let line: StatLine
    let isOpen: Bool

    private var tint: Color {
        switch line.app {
        case .macroTrack: HubItem.Kind.meal.color
        case .knowledge: HubItem.Kind.study.color
        default: HubItem.Kind.lift.color
        }
    }

    private var trendColor: Color {
        switch line.trend {
        case .ahead, .onPace: .green
        case .stalled: .orange
        case .regressing: .red
        case .notEnoughData: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.stat.label).font(.body.weight(.semibold))
                Spacer()
                Text(line.score.map(String.init) ?? "–").font(.body.weight(.bold)).monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(line.label).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if line.isKnown { Text(line.trend.label).font(.caption).foregroundStyle(trendColor) }
            }
            StatBar(score: line.score ?? 0, tint: tint)
            if isOpen {
                ForEach(line.sources) { source in
                    LabeledContent(source.app.displayName) {
                        Text(source.score.map { "\($0), \(source.label)" } ?? source.label)
                    }
                    .font(.footnote)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

struct StatBar: View {
    let score: Int
    let tint: Color

    var body: some View {
        Capsule()
            .fill(.insetBackground)
            .frame(height: 6)
            .overlay {
                Rectangle()
                    .fill(tint)
                    .scaleEffect(x: Double(score) / 100, anchor: .leading)
            }
            .clipShape(.capsule)
            .padding(.top, 3)
            .accessibilityHidden(true)
    }
}
