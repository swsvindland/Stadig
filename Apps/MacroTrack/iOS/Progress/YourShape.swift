import SwiftUI
import SystemCore
import SystemStore

/// The six scores, read from what both apps publish. Stadig Macro measures Vitality and half of
/// Discipline; Stadig Lift the rest, which show once it's set up on this phone too.
@MainActor
@Observable
final class ShapeScores {
    private(set) var lines: [StatLine] = []
    private(set) var bothApps = false

    func read(_ model: AppModel) {
        lines = StatsBoard.lines(shared: model.shared, today: model.today)
        bothApps = StatsBoard.bothApps(shared: model.shared, today: model.today)
    }

    /// Measured scores first, each group in the board's order; the figure keeps its fixed corners.
    var rows: [StatLine] { lines.filter { $0.score != nil } + lines.filter { $0.score == nil } }

    var summary: String {
        let known = lines.filter { $0.score != nil }.count
        if known == lines.count || lines.isEmpty { return "Six scores, one figure. It grows where you do the work." }
        if bothApps { return "\(known) of six scores so far. The rest fill in as you log and train." }
        return "\(known == 1 ? "One score" : "\(known) scores") from your food. Stadig Lift measures the rest."
    }
}

/// The figure, its line, and a row each: which app measures it, and what it says.
private struct ShapeBody: View {
    let scores: ShapeScores

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(scores.summary).font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            ScoreShape(axes: ScoreShape.axes(scores.lines))
                // Its corner labels sit outside the figure at a fixed reach: past the largest
                // standard size they run off the screen. The rows below say every score at any size.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(maxWidth: 360)
                .frame(maxWidth: .infinity)
            VStack(spacing: 0) {
                ForEach(Array(scores.rows.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { Rectangle().fill(Ink.hairline).frame(height: 1) }
                    ShapeRow(line: line, bothApps: scores.bothApps)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

/// A score: its number, its name and which app measures it, what it says, and where it's heading.
private struct ShapeRow: View {
    let line: StatLine
    let bothApps: Bool

    var body: some View {
        let lift = line.sources.isEmpty && line.app == .liftTrack && !bothApps
        HStack(alignment: .center, spacing: 12) {
            Text(line.score.map(String.init) ?? "–")
                .numeral(20)
                .foregroundStyle(line.score == nil ? Ink.text3 : Ink.text)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(line.stat.label).font(.subheadline.weight(.semibold)).foregroundStyle(line.score == nil ? Ink.text2 : Ink.text)
                    SourceChip(apps: line.apps.isEmpty ? [line.app] : line.apps)
                }
                Text(lift ? "Measured by Stadig Lift. Also free." : line.label)
                    .font(.caption).foregroundStyle(Ink.text3).lineLimit(2)
            }
            Spacer(minLength: 4)
            if let trend = Self.trend(line.trend) {
                Text(trend.0).font(.caption.weight(.semibold)).foregroundStyle(trend.1)
            }
        }
        .frame(minHeight: 50)
        .padding(.vertical, 4)
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

/// Your shape in a card, where there's room for it at the top of Progress.
struct YourShapeCard: View {
    @Environment(AppModel.self) private var model
    @State private var scores = ShapeScores()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your shape").font(.title2.weight(.bold)).foregroundStyle(Ink.text).padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            ShapeBody(scores: scores)
        }
        .inkCard(padding: 18)
        .accessibilityIdentifier("progress.shape")
        // The other app's summary is read from the shared container: again whenever the analysis
        // (and this app's own summary with it) changes.
        .task(id: model.analysisVersion) { scores.read(model) }
    }
}

/// The way into Your shape at the top of a phone's Progress: the figure small, and the scores this
/// app has in a line.
struct YourShapeRow: View {
    @Environment(AppModel.self) private var model
    @State private var scores = ShapeScores()
    @State private var opened = false
    /// Once a launch: back on Progress, the page isn't opened again.
    private static var openedOnLaunch = false

    var body: some View {
        Button {
            opened = true
        } label: {
            HStack(spacing: 14) {
                ScoreShape(axes: ScoreShape.axes(scores.lines), showsLabels: false)
                    .frame(width: 58, height: 54)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your shape").font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                    Text(line).font(.caption.monospacedDigit()).foregroundStyle(Ink.text3).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Ink.text3)
            }
            .padding(.vertical, 10)
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your shape. \(line)")
        .accessibilityIdentifier("progress.shape")
        .navigationDestination(isPresented: $opened) { YourShapeScreen() }
        .task(id: model.analysisVersion) { scores.read(model) }
        .task {
            #if DEBUG
            // -showShape, with -tab progress: a phone's Your shape page, for checking it.
            guard !Self.openedOnLaunch, LaunchOptions.current.has("-showShape") else { return }
            Self.openedOnLaunch = true
            opened = true
            #endif
        }
    }

    /// "Vitality 92 · Discipline 28".
    var line: String {
        let known = scores.rows.filter { $0.score != nil }
        guard !known.isEmpty else { return "Six scores, one figure" }
        return known.prefix(3).map { "\($0.stat.label) \($0.score ?? 0)" }.joined(separator: " · ")
    }
}

/// The six scores on a page of their own, opened from Progress.
struct YourShapeScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var scores = ShapeScores()

    var body: some View {
        // The Mac reports no size class: it always has room.
        let wide = sizeClass != .compact
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !wide { DetailHeader(eyebrow: "Progress", title: "Your shape") }
                ShapeBody(scores: scores)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableWidth(560)
        }
        .background(.pageBackground)
        .detailPage(title: "Your shape", wide: wide)
        .pushedPage()
        .accessibilityIdentifier("progress.shapeScreen")
        .task(id: model.analysisVersion) { scores.read(model) }
    }
}
