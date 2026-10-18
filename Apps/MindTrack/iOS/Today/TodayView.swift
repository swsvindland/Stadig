import MindEngine
import SwiftUI
import SystemCore

/// The day's session and the one or two other things worth doing. Most visits are a glance and a
/// tap on Start.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let analysis = model.analysis {
                        Pill(text: analysis.phase.label, symbol: phaseSymbol(analysis.phase), color: analysis.phase.isReview ? .teal : .accentColor)
                        if case .paused(let kind) = analysis.phase {
                            PausedCard(kind: kind)
                        } else if let plan = analysis.today {
                            SessionCard(plan: plan)
                        } else if let done = analysis.doneToday.last(where: \.planned) ?? analysis.doneToday.last {
                            DoneCard(session: done)
                        } else {
                            RestCard()
                        }
                        ForEach(analysis.actions) { ActionCard(action: $0) }
                        if !analysis.learned.isEmpty {
                            SectionHeader(title: "What we've learned")
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(analysis.learned, id: \.self) { Text($0).font(.subheadline) }
                            }
                            .card()
                        }
                        Glance(analysis: analysis)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .readableWidth()
            }
            .background(.pageBackground)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") { model.showSettings = true }
                        .accessibilityIdentifier("today.settings")
                }
            }
        }
    }

    func phaseSymbol(_ phase: StudyPhase) -> String {
        switch phase {
        case .assessment: "scope"
        case .loading: "chart.bar.fill"
        case .review: "arrow.triangle.2.circlepath"
        case .paused(let kind): kind.symbol
        }
    }
}

private struct SessionCard: View {
    @Environment(AppModel.self) private var model
    let plan: SessionPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(plan.domains.filter { domain in plan.kind != .checkIn || plan.parts.contains { $0.domain == domain } }, id: \.self) {
                    DomainBadge(domain: $0, size: 32)
                }
                Spacer()
                if plan.kind != .regular { Pill(text: plan.kind.label, color: .accentColor) }
            }
            Text(plan.headline).font(.title2.bold())
                .accessibilityIdentifier("today.headline")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(plan.parts) { part in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: part.domain?.symbol ?? "arrow.triangle.2.circlepath")
                            .foregroundStyle(part.domain?.color ?? .secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(part.title).font(.subheadline.weight(.semibold))
                            Text(part.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.minutes(Double(part.minutes))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            if !plan.notes.isEmpty { WhyDisclosure(reasons: plan.notes) }
            Button {
                model.startToday()
            } label: {
                Text(plan.kind == .checkIn ? "Start the check-in" : "Start").font(.headline).frame(maxWidth: .infinity)
            }
            .primaryAction()
            .controlSize(.large)
            .accessibilityIdentifier("today.start")
        }
        .card(padding: 18)
    }
}

private struct DoneCard: View {
    @Environment(AppModel.self) private var model
    let session: StudySession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Done for today", systemImage: "checkmark.circle.fill").font(.title3.bold()).foregroundStyle(.green)
                .accessibilityIdentifier("today.done")
            Text("\(Format.minutes(session.minutes)) of \(ListFormatter.localizedString(byJoining: session.domains.map(\.label))).")
                .foregroundStyle(.secondary)
            StudyMoreMenu()
        }
        .card(padding: 18)
    }
}

private struct RestCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Rest day", systemImage: "moon.zzz.fill").font(.title3.bold())
                .accessibilityIdentifier("today.rest")
            Text("Rest is part of the plan, and spacing is what makes memory stick. Nothing is expected today.")
                .foregroundStyle(.secondary)
            StudyMoreMenu()
        }
        .card(padding: 18)
    }
}

private struct PausedCard: View {
    let kind: LifeModeKind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mind Track is paused", systemImage: kind.symbol).font(.title3.bold())
                .accessibilityIdentifier("today.paused")
            Text(detail).foregroundStyle(.secondary)
        }
        .card(padding: 18)
    }

    var detail: String {
        switch kind {
        case .vacation:
            "On vacation: nothing is expected, and these days never count against you. Watch something in a language you're learning if you feel like it."
        case .illness: "Get better. Nothing is expected, and the days don't count."
        case .crunch: "Crunch mode pauses study. A five-minute review is here if you want it; nothing is expected."
        case .injury: ""
        }
    }
}

/// Another session on a rest day or after the planned one: any domain.
private struct StudyMoreMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let settings = model.settings {
            Menu {
                ForEach(settings.domains) { domain in
                    Button(domain.label, systemImage: domain.symbol) {
                        model.startSession(domain == .maths && settings.has(.writing) ? [.maths, .writing] : [domain])
                    }
                    .accessibilityIdentifier("today.studyAnyway.\(domain.rawValue)")
                }
                if (model.analysis?.dueToday ?? 0) > 0 {
                    Button("Five minutes of reviews", systemImage: "arrow.triangle.2.circlepath") { model.startExtraReview() }
                        .accessibilityIdentifier("today.studyAnyway.reviews")
                }
            } label: {
                Label("Study anyway", systemImage: "plus")
            }
            .secondaryAction()
            .accessibilityIdentifier("today.studyAnyway")
        }
    }
}

/// Something worth doing today, and the button that starts it.
struct ActionCard: View {
    @Environment(AppModel.self) private var model
    let action: MindAction

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(action.title).font(.headline)
            Text(action.detail).font(.subheadline).foregroundStyle(.secondary)
            Button(Self.buttonTitle(action.command)) { Self.perform(action.command, model: model) }
                .secondaryAction()
                .accessibilityIdentifier("today.action.\(action.id)")
        }
        .card()
    }

    static func buttonTitle(_ command: MindAction.Command) -> String {
        switch command {
        case .extraReview(let minutes): "\(spelledOut(minutes)) minutes of reviews"
        case .pickBook: "Choose a book"
        case .stalledBook: "Open the shelf"
        case .catchUp: "Catch up now"
        case .episode: "I watched one"
        }
    }

    /// Written out ("Ten"), as the menu's "Five minutes of reviews" and the actions' own titles write
    /// a few minutes. In English whatever the region, like the words around it.
    private static func spelledOut(_ count: Int) -> String {
        let words = spellOut.string(from: count as NSNumber) ?? "\(count)"
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    private static let spellOut: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en")
        return formatter
    }()

    static func perform(_ command: MindAction.Command, model: AppModel) {
        switch command {
        case .extraReview(let minutes): model.startExtraReview(minutes: minutes)
        case .pickBook, .stalledBook: model.showShelf = true
        case .episode(let language): model.episodeLanguage = language
        case .catchUp(let domains): model.startSession(domains)
        }
    }
}

/// The two stats, quietly, at the bottom.
private struct Glance: View {
    let analysis: MindAnalysis

    var body: some View {
        if !analysis.stats.isEmpty {
            HStack(spacing: 12) {
                ForEach(analysis.stats, id: \.stat) { reading in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: reading.stat.symbol)
                            Text(reading.stat.label).font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: reading.trend.symbol).foregroundStyle(reading.trend.color)
                        }
                        Text(reading.score.map { "\(Int($0.rounded()))" } ?? "—").font(.title.bold().monospacedDigit())
                        Text(reading.label).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    .card(padding: 14)
                }
            }
            .padding(.top, 6)
        }
    }
}

/// An episode watched without subtitles, or a real conversation: how much did it make sense?
struct EpisodeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let language: Language
    @State private var test = TestKind.episode
    @State private var title = ""
    @State private var rating = 1

    let options = ["Lost most of it", "Caught bits and pieces", "Followed most of it", "Followed nearly all of it"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("What was it?", selection: $test) {
                        Text("An episode").tag(TestKind.episode)
                        Text("A conversation").tag(TestKind.conversation)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("episode.kind")
                    TextField(test == .episode ? "What did you watch? (optional)" : "Who with, or where? (optional)", text: $title)
                        .accessibilityIdentifier("episode.title")
                }
                Section {
                    Picker("How much did you follow?", selection: $rating) {
                        ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("How much did you follow?")
                } footer: {
                    Text(
                        "A plain check-in, not a score: it's how you'll see real \(language.domain.label) start to open up. The listening and speaking tests are what measure."
                    )
                }
            }
            .navigationTitle(language.domain.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("episode.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.logEpisode(rating: rating, title: title, language: language, test: test)
                        dismiss()
                    }
                    .accessibilityIdentifier("episode.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
