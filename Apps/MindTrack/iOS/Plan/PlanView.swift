import SwiftUI
import MindEngine
import SystemCore

/// The week, the block, and what comes next in each subject.
struct PlanView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let analysis = model.analysis, let state = model.state {
                        BlockCard(analysis: analysis, state: state)
                        WeekStrip(days: analysis.week, today: model.today)
                        ForEach(analysis.languages, id: \.domain) { LanguagePlanCard(summary: $0, state: state) }
                        if state.settings.has(.maths) { MathsPlanCard(state: state) }
                        if state.settings.has(.writing) { WritingPlanCard(analysis: analysis, state: state) }
                        if state.settings.has(.reading) { ReadingPlanCard(analysis: analysis) }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .readableWidth()
            }
            .background(.pageBackground)
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") { model.showSettings = true }
                        .accessibilityIdentifier("plan.settings")
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
            if state.calendar != nil {
                Label("Review weeks follow Lift Track's deloads", systemImage: "link").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    var detail: String {
        switch analysis.phase {
        case .assessment:
            return "The first two weeks find a level in each subject. Every session is a normal one; placement happens inside them."
        case .review(let end):
            return "Nothing new until \(Format.day(end.adding(days: 1))): reviews, practice and reading for pleasure. The check-in lands at the end, when you're fresh."
        case .loading:
            if let next = StudyCalendar.nextReview(from: state.today, start: state.start, calendar: state.calendar) {
                return "New material every session, as fast as it sticks. Review week starts \(Format.day(next.start))."
            }
            return "New material every session, as fast as it sticks."
        case .paused(let kind):
            return "\(kind.label): nothing is expected, and these days don't count."
        }
    }
}

struct WeekStrip: View {
    let days: [StudyDay]
    let today: Day

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Text(day.day.weekday.short).font(.caption2.weight(.semibold)).foregroundStyle(day.day == today ? Color.accentColor : .secondary)
                    VStack(spacing: 3) {
                        ForEach(day.domains, id: \.self) { DomainBadge(domain: $0, size: 24).opacity(day.status == .missed ? 0.35 : 1) }
                        if day.domains.isEmpty { Circle().fill(Color.secondary.opacity(0.15)).frame(width: 24, height: 24) }
                    }
                    Image(systemName: symbol(day.status)).font(.caption2).foregroundStyle(color(day.status))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(day.day == today ? Color.accentColor.opacity(0.1) : .clear, in: .rect(cornerRadius: 12))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.day.weekday.name): \(day.domains.isEmpty ? "rest" : day.domains.map(\.label).joined(separator: " and ")), \(label(day.status))")
            }
        }
        .card(padding: 10)
    }

    func symbol(_ status: StudyDay.Status) -> String {
        switch status {
        case .done: "checkmark.circle.fill"
        case .missed: "minus.circle"
        case .today: "circle.dotted"
        case .planned: "circle"
        case .rest: "moon"
        case .paused: "pause.circle"
        }
    }

    func color(_ status: StudyDay.Status) -> Color { status == .done ? .green : .secondary }

    func label(_ status: StudyDay.Status) -> String {
        switch status {
        case .done: "done"
        case .missed: "missed"
        case .today: "today"
        case .planned: "planned"
        case .rest: "rest"
        case .paused: "paused"
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
