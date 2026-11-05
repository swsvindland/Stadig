import MindEngine
import SwiftUI
import SystemCore

/// The week, the block, and what comes next in each subject.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let analysis = model.analysis, let state = model.state {
                        BlockCard(analysis: analysis, state: state)
                        WeekCard(week: state.week, analysis: analysis, state: state)
                        // Each course's card, in columns in a wide window.
                        CardColumns {
                            ForEach(analysis.languages, id: \.domain) { LanguagePlanCard(summary: $0, state: state) }
                            if state.settings.has(.maths) { MathsPlanCard(state: state) }
                            if state.settings.has(.writing) { WritingPlanCard(analysis: analysis, state: state) }
                            if state.settings.has(.reading) { ReadingPlanCard(analysis: analysis) }
                        }
                    }
                }
                .padding(.horizontal, sizeClass == .regular ? 24 : 16)
                .padding(.bottom, 24)
                .pageWidth(sizeClass)
            }
            .background(.pageBackground)
            .navigationTitle("Plan")
            .toolbar {
                if !Platform.isMac {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Settings", systemImage: "gearshape") { model.showSettings = true }
                            .accessibilityIdentifier("plan.settings")
                    }
                }
            }
        }
    }
}

private struct BlockCard: View {
    let analysis: MindAnalysis
    let state: StudyState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(analysis.phase.label).font(.title2.bold())
                .accessibilityIdentifier("plan.phase")
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
            if !state.settings.maintenance.isEmpty {
                Label(
                    "\(ListFormatter.localizedString(byJoining: state.settings.maintenance.map(\.label))): reviews only",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            if state.calendar != nil {
                Label("Review weeks follow Stadig Lift's deloads", systemImage: "link").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    var detail: String {
        switch analysis.phase {
        case .assessment:
            return "The first two weeks find a level in each subject. A course's first block is its placement; the rest are normal blocks."
        case .review(let end):
            return
                "Nothing new until \(Format.day(end.adding(days: 1))): reviews, practice and reading for pleasure. The check-in lands at the end, when you're fresh."
        case .loading:
            if let next = StudyCalendar.nextReview(from: state.today, start: state.start, calendar: state.calendar) {
                return "New material every block, as fast as it sticks. Review week starts \(Format.day(next.start))."
            }
            return "New material every block, as fast as it sticks."
        case .paused(let kind):
            return "\(kind.label): nothing is expected, and these days don't count."
        }
    }
}

/// The week's grid, what's left of it, and what doesn't fit.
private struct WeekCard: View {
    @Environment(AppModel.self) private var model
    let week: WeekSettings
    let analysis: MindAnalysis
    let state: StudyState
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let follows = WeekPlanner.followsRhythm(state)
            WeekGrid(
                cells: WeekPlanner.cells(state, settings: week, layout: analysis.layout), today: state.today.weekday,
                toggle: follows ? nil : { model.togglePart($0.weekday, $0.part) })
            if analysis.layout.leftoverCount > 0 {
                let count = analysis.layout.leftoverCount
                Label("\(count) block\(count == 1 ? "" : "s") won't fit this week", systemImage: "tray.full")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("plan.leftovers")
            }
            if follows {
                Text("This week fits around your rhythm in Stadig. Anything missed moves to the next open part.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("plan.rhythm")
                Button("Open your rhythm") {
                    if let url = URL(string: "stadig://rhythm") { openURL(url) }
                }
                .font(.footnote)
                .accessibilityIdentifier("plan.openRhythm")
            } else {
                Text("Tap a part of the week to open or close it. Anything missed moves to the next open part.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct DomainHeader: View {
    let domain: Domain
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            DomainBadge(domain: domain)
            Text(domain.label).font(.headline)
            Spacer()
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}
