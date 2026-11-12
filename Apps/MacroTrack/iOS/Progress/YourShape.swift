import SwiftUI
import SystemCore
import SystemStore

/// The six scores as one figure, and a row each: which app measures it, and what it says. Stadig
/// Macro measures Vitality and half of Discipline; Stadig Lift the rest, which show once it's set up
/// on this phone too.
struct YourShapeCard: View {
    @Environment(AppModel.self) private var model
    @State private var lines: [StatLine] = []
    @State private var bothApps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your shape").font(.title2.weight(.bold)).foregroundStyle(Ink.text)
                Text(summary).font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
            }
            ScoreShape(axes: ScoreShape.axes(lines))
                .frame(maxWidth: 360)
                .frame(maxWidth: .infinity)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { Divider().overlay(Ink.hairline) }
                    row(line)
                }
            }
        }
        .inkCard(padding: 18)
        .accessibilityIdentifier("progress.shape")
        // The other app's summary is read from the shared container: again whenever the analysis
        // (and this app's own summary with it) changes.
        .task(id: model.analysisVersion) { read() }
    }

    /// Measured scores first, each group in the board's order; the figure keeps its fixed corners.
    var rows: [StatLine] { lines.filter { $0.score != nil } + lines.filter { $0.score == nil } }

    var summary: String {
        let known = lines.filter { $0.score != nil }.count
        if known == lines.count || lines.isEmpty { return "Six scores, one figure. It grows where you do the work." }
        if bothApps { return "\(known) of six scores so far. The rest fill in as you log and train." }
        return "\(known == 1 ? "One score" : "\(known) scores") from your food. Stadig Lift measures the rest."
    }

    func read() {
        lines = StatsBoard.lines(shared: model.shared, today: model.today)
        bothApps = StatsBoard.bothApps(shared: model.shared, today: model.today)
    }

    func row(_ line: StatLine) -> some View {
        let lift = line.sources.isEmpty && line.app == .liftTrack && !bothApps
        return HStack(alignment: .center, spacing: 14) {
            Text(line.score.map(String.init) ?? "–")
                .numeral(22)
                .foregroundStyle(line.score == nil ? Ink.text3 : Ink.text)
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(line.stat.label).font(.subheadline.weight(.semibold)).foregroundStyle(line.score == nil ? Ink.text2 : Ink.text)
                    SourceChip(apps: line.apps.isEmpty ? [line.app] : line.apps)
                }
                Text(lift ? "Measured by Stadig Lift. Also free." : line.label)
                    .font(.caption).foregroundStyle(Ink.text2).lineLimit(2)
            }
            Spacer(minLength: 4)
            if let trend = Self.trend(line.trend) {
                Text(trend.0).font(.caption.weight(.semibold)).foregroundStyle(trend.1)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress.shape.\(line.stat.rawValue)")
    }

    /// A word for where a score is heading, coloured only where it means something.
    static func trend(_ trajectory: Trajectory) -> (String, Color)? {
        switch trajectory {
        case .ahead: ("rising", Ink.good)
        case .onPace: ("steady", Ink.text2)
        case .stalled: ("stalled", Ink.ok)
        case .regressing: ("slipping", Ink.bad)
        case .notEnoughData: nil
        }
    }
}
