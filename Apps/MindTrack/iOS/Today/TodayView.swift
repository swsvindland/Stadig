import MindEngine
import SwiftUI
import SystemCore

/// The day's session and the one or two other things worth doing. Most visits are a glance and a
/// tap on Start.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                if let analysis = model.analysis {
                    if sizeClass == .regular {
                        // The session and what to do beside what's been learned and the two stats,
                        // when there's room for both; one column in a narrow window (the Mac's at its
                        // smallest beside the sidebar, an iPad in a two-thirds split).
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 18) {
                                VStack(alignment: .leading, spacing: 14) { main(analysis) }
                                    .frame(minWidth: 420, idealWidth: 480, maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .leading, spacing: 14) { side(analysis, column: true) }
                                    .frame(width: 340)
                            }
                            VStack(alignment: .leading, spacing: 14) {
                                main(analysis)
                                side(analysis)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .pageWidth(sizeClass)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            main(analysis)
                            side(analysis)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                        .readableWidth()
                    }
                }
            }
            .background(.pageBackground)
            .navigationTitle("Today")
            .toolbar {
                // The Mac's settings are in the menu bar (⌘,), as a Mac app's are.
                if !Platform.isMac {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Settings", systemImage: "gearshape") { model.showSettings = true }
                            .accessibilityIdentifier("today.settings")
                    }
                }
            }
        }
    }

    @ViewBuilder func main(_ analysis: MindAnalysis) -> some View {
        Pill(text: analysis.phase.label, symbol: phaseSymbol(analysis.phase), color: analysis.phase.isReview ? .teal : .accentColor)
        if Platform.isMac, model.sessionOpen {
            OpenSessionCard()
        } else if case .paused(let kind) = analysis.phase {
            PausedCard(kind: kind)
        } else {
            if let plan = analysis.today {
                SessionCard(plan: plan, part: analysis.blocks.first { !$0.done }?.part)
            } else if let done = analysis.doneToday.last(where: \.planned) ?? analysis.doneToday.last {
                DoneCard(session: done)
            } else {
                RestCard(commitments: analysis.commitments)
            }
            TodayRest(analysis: analysis)
        }
        if let line = model.dayAhead { HubStrip(line: line).card(padding: 12) }
        // What's worth doing next waits on the Mac while a session is open beside it: each starts
        // another session or opens the shelf, and neither runs beside one.
        if !model.sessionOpen {
            ForEach(analysis.actions) { ActionCard(action: $0) }
        }
    }

    /// What's been learned and the two stats: under the session, or in a column of their own beside
    /// it, where the stats stack (side by side, "Intelligence" breaks over two lines).
    @ViewBuilder func side(_ analysis: MindAnalysis, column: Bool = false) -> some View {
        if !analysis.learned.isEmpty {
            SectionHeader(title: "What we've learned")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(analysis.learned, id: \.self) { Text($0).font(.subheadline) }
            }
            .card()
        }
        Glance(analysis: analysis, stacked: column)
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

/// Everything else on Today after the next block: the day's other blocks, check-ins, reviews-only
/// courses, and a conversation to log.
private struct TodayRest: View {
    @Environment(AppModel.self) private var model
    let analysis: MindAnalysis

    /// The day's blocks other than the next one, those to come first.
    var others: [TodayBlock] {
        let next = analysis.blocks.first { !$0.done }
        return analysis.blocks.filter { $0.id != next?.id }.sorted { (!$0.done ? 0 : 1, $0.part) < (!$1.done ? 0 : 1, $1.part) }
    }

    var body: some View {
        let others = others
        let offers = analysis.checkIns + analysis.reviewsOnly
        if !others.isEmpty || !offers.isEmpty {
            VStack(spacing: 0) {
                ForEach(others) { BlockRow(block: $0) }
                ForEach(offers, id: \.headline) { OfferRow(plan: $0) }
            }
            .card(padding: 0)
        }
        if let languages = model.settings?.languages, !languages.isEmpty, !model.sessionOpen {
            ConversationButton(languages: languages)
        }
    }
}

/// A later block of the day, or one that's done.
private struct BlockRow: View {
    @Environment(AppModel.self) private var model
    let block: TodayBlock

    var body: some View {
        HStack(spacing: 12) {
            DomainBadge(domain: block.domain, size: 30).opacity(block.done ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.plan?.headline ?? block.domain.label).font(.subheadline.weight(.semibold))
                Text(block.part.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if block.done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Done")
            } else {
                Button("Start") { model.startBlock(block.domain) }
                    .secondaryAction()
                    .disabled(model.sessionOpen)
                    .accessibilityLabel("Start \(block.domain.label)")
                    .accessibilityIdentifier("today.block.\(block.domain.rawValue)")
            }
        }
        .padding(14)
        .accessibilityElement(children: .contain)
    }
}

/// A check-in, or a short session for a course with no blocks.
private struct OfferRow: View {
    @Environment(AppModel.self) private var model
    let plan: SessionPlan

    var body: some View {
        HStack(spacing: 12) {
            if let domain = plan.domains.first { DomainBadge(domain: domain, size: 30) }
            VStack(alignment: .leading, spacing: 1) {
                Text(plan.headline).font(.subheadline.weight(.semibold))
                Text(plan.kind == .checkIn ? "The plain tests: these are what move your stats" : "Optional").font(.caption).foregroundStyle(
                    .secondary)
            }
            Spacer()
            Button("Start") { model.startOffered(plan) }
                .secondaryAction()
                .disabled(model.sessionOpen)
                .accessibilityLabel("Start \(plan.headline)")
                .accessibilityIdentifier("today.offer.\(plan.kind.rawValue).\(plan.domains.first?.rawValue ?? "")")
        }
        .padding(14)
        .accessibilityElement(children: .contain)
    }
}

/// A real conversation away from the app, a commute's talking with a friend or Claude, counts as a
/// block. Nothing happens if it's never pressed.
private struct ConversationButton: View {
    @Environment(AppModel.self) private var model
    let languages: [Domain]
    @State private var asking: Domain?

    var body: some View {
        Group {
            if languages.count == 1, let language = languages.first {
                Button("Log a \(language.label) conversation", systemImage: "bubble.left.and.bubble.right") { asking = language }
            } else {
                Menu("Log a conversation", systemImage: "bubble.left.and.bubble.right") {
                    ForEach(languages) { language in
                        Button(language.label) { asking = language }
                    }
                }
            }
        }
        .secondaryAction()
        .accessibilityIdentifier("today.logConversation")
        .confirmationDialog(
            "Count \(StudySession.conversationMinutes) minutes of real conversation as a block?",
            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }), titleVisibility: .visible, presenting: asking
        ) { language in
            Button("Count it") { model.logConversation(language) }
                .accessibilityIdentifier("today.logConversation.confirm")
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct SessionCard: View {
    @Environment(AppModel.self) private var model
    let plan: SessionPlan
    /// The part of the day the block is planned for.
    var part: DayPart?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(plan.domains, id: \.self) { DomainBadge(domain: $0, size: 32) }
                if let part { Text(part.label).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("today.part") }
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
            .help(Platform.isMac ? "Opens the session in its own window (⌘N)" : "")
            .accessibilityIdentifier("today.start")
        }
        .card(padding: 18)
    }
}

/// On the Mac a session runs in its own window: this brings it forward.
private struct OpenSessionCard: View {
    @Environment(AppModel.self) private var model
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("A session is open", systemImage: "rectangle.on.rectangle").font(.title3.bold())
                .accessibilityIdentifier("today.sessionOpen")
            if let run = model.run, let part = run.currentPart {
                Text("\(part.title), part \(run.partIndex + 1) of \(run.planParts.count). \(Format.minutes(max(0, run.minutesLeft))) left.")
                    .foregroundStyle(.secondary)
            }
            Button("Go to the Session", systemImage: "arrow.up.forward.app") {
                #if os(macOS)
                openWindow(id: SessionWindow.id)
                #endif
            }
            .secondaryAction()
            .accessibilityIdentifier("today.showSession")
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
    /// What fills the day, when something does.
    var commitments: [Commitment] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Rest day", systemImage: "moon.zzz.fill").font(.title3.bold())
                .accessibilityIdentifier("today.rest")
            Text(detail).foregroundStyle(.secondary)
                .accessibilityIdentifier("today.restDetail")
            StudyMoreMenu()
        }
        .card(padding: 18)
    }
}

extension RestCard {
    var detail: String {
        let held = commitments.map(\.title)
        guard !held.isEmpty else { return "Rest is part of the plan, and spacing is what makes memory stick. Nothing is expected today." }
        return "\(ListFormatter.localizedString(byJoining: held)) today, so no study is planned. Anything you do still counts for the week."
    }
}

private struct PausedCard: View {
    let kind: LifeModeKind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Stadig Mind is paused", systemImage: kind.symbol).font(.title3.bold())
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
                        model.startBlock(domain)
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
        }
    }
}

/// The two stats, quietly, at the bottom.
private struct Glance: View {
    let analysis: MindAnalysis
    /// One above the other, in a column too narrow for two.
    var stacked = false

    var body: some View {
        if !analysis.stats.isEmpty {
            Group {
                if stacked {
                    VStack(spacing: 12) { cards }
                } else {
                    HStack(spacing: 12) { cards }
                }
            }
            .padding(.top, 6)
        }
    }

    var cards: some View {
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
            .inlineTitle()
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
        .sheetForm(height: 460)
    }
}
