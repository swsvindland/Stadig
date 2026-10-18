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

private struct LanguagePlanCard: View {
    @Environment(AppModel.self) private var model
    let summary: LanguageSummary
    let state: StudyState

    var domain: Domain { summary.domain }

    var body: some View {
        let retention = summary.retention
        let due = state.cards.values.filter { $0.domain == domain && ($0.memory.map { Day($0.due) <= state.today.adding(days: 6) } ?? false) }.count
        let pace = LanguagePlan.newWords(retention: retention, dueThisWeek: due, minutes: state.settings.schedule.minutes, reviewWeek: false)
        VStack(alignment: .leading, spacing: 12) {
            DomainHeader(domain: domain, detail: "\(summary.wordsLearned) words in")
            if model.catalogs.deck(for: domain) == nil {
                Text("The \(domain.label) catalog isn't installed in this build.").font(.subheadline).foregroundStyle(.secondary)
            } else if summary.mode == .maintenance {
                LabeledContent("Maintenance", value: "Reviews only")
                LabeledContent("Due this week", value: "\(due)")
                LabeledContent("Recall on reviews", value: retention.map(Format.percent) ?? "Not enough yet")
            } else {
                LabeledContent("New words a session", value: "\(pace.count)")
                LabeledContent("Recall on reviews", value: retention.map(Format.percent) ?? "Not enough yet")
                if let reason = pace.reason { Text(reason).font(.footnote).foregroundStyle(.secondary) }
                let upcoming = upcomingWords
                if !upcoming.isEmpty {
                    Text("Coming up").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(upcoming) { word in
                            VStack(spacing: 0) {
                                Text(word.text).font(.title3)
                                Text(word.meaning).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.insetBackground, in: .rect(cornerRadius: 10))
                        }
                    }
                }
            }
        }
        .font(.subheadline)
        .card()
    }

    var upcomingWords: [Word] {
        guard let deck = model.catalogs.deck(for: domain), let language = domain.language else { return [] }
        let items = LanguagePlan.next(count: 8, cards: Set(state.cards.keys), deck: deck, readsKana: language == .japanese ? state.settings.readsKana : true,
                                      frontier: LanguagePlan.frontier(state.tests, language))
        return items.compactMap { item in
            switch item {
            case .teach(let word): word
            case .probe, .kana: nil
            }
        }
    }
}

private struct MathsPlanCard: View {
    let state: StudyState

    var body: some View {
        let known = MathsPlan.known(state.cards)
        let progress = MathsPlan.inProgress(state.cards)
        let frontier = MathsPlan.frontier(state.cards)
        VStack(alignment: .leading, spacing: 12) {
            DomainHeader(domain: .maths, detail: "\(known.count) of \(MathCurriculum.topics.count) topics")
            if !progress.isEmpty {
                Text("Carrying on").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(progress) { TopicRow(topic: $0, status: "Started") }
            }
            if !frontier.isEmpty {
                Text("Next, once the last one sticks").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(frontier.prefix(4)) { TopicRow(topic: $0, status: "Level \($0.level)") }
            }
            NavigationLink {
                TopicMap(state: state)
            } label: {
                Label("All topics", systemImage: "point.3.connected.trianglepath.dotted")
            }
        }
        .font(.subheadline)
        .card()
    }
}

private struct TopicRow: View {
    let topic: MathTopic
    let status: String

    var body: some View {
        HStack {
            Text(topic.title)
            Spacer()
            Text(status).foregroundStyle(.secondary)
        }
    }
}

/// Every maths topic by level, and where each stands.
struct TopicMap: View {
    let state: StudyState

    var body: some View {
        let known = MathsPlan.known(state.cards)
        let started = Set(state.cards.values.filter { $0.domain == .maths }.map(\.key.item))
        let next = Set(MathsPlan.frontier(state.cards).map(\.id))
        List {
            ForEach(1...MathCurriculum.maxLevel, id: \.self) { level in
                Section("Level \(level)") {
                    ForEach(MathCurriculum.topics.filter { $0.level == level }) { topic in
                        HStack {
                            Text(topic.title)
                            Spacer()
                            if known.contains(topic.id) {
                                Label("Known", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly).foregroundStyle(.green)
                            } else if started.contains(topic.id) {
                                Text("Started").foregroundStyle(.secondary)
                            } else if next.contains(topic.id) {
                                Text("Ready").foregroundStyle(Color.accentColor)
                            } else {
                                Image(systemName: "lock").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Maths topics")
    }
}

private struct ReadingPlanCard: View {
    @Environment(AppModel.self) private var model
    let analysis: MindAnalysis

    var body: some View {
        let reading = analysis.reading
        VStack(alignment: .leading, spacing: 10) {
            DomainHeader(domain: .reading, detail: reading.comfortTier.map { "Comfortable at tier \($0)" })
            if let book = reading.current {
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(.headline)
                    Text("\(book.author) · tier \(book.tier)").foregroundStyle(.secondary)
                    ProgressView(value: book.progress).tint(.teal)
                    Text("Page \(book.page) of \(book.pages)").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("No book on the go. The ladder suggests tier \(reading.targetTier) next.").foregroundStyle(.secondary)
            }
            Button("Your shelf", systemImage: "books.vertical") { model.showShelf = true }
        }
        .font(.subheadline)
        .card()
    }
}

/// Books: the one on the go, what the ladder suggests, and what's been read.
struct ShelfView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Book?
    @State private var adding = false
    @State private var finishing: Book?

    var body: some View {
        let shelf = model.books
        List {
            if let current = shelf.first(where: { $0.status == .reading }) {
                Section("Reading now") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(current.title).font(.headline)
                        Text("\(current.author) · tier \(current.tier) · page \(current.page) of \(current.pages)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button("Finished it", systemImage: "checkmark") { finishing = current }
                    Button("Edit", systemImage: "pencil") { editing = current }
                    Button("Set it aside", systemImage: "xmark.bin", role: .destructive) {
                        var book = current
                        book.status = .abandoned
                        book.finished = model.today
                        model.save(book: book)
                    }
                }
            }
            Section {
                ForEach(ReadingPlan.suggestions(shelf: shelf, genres: model.settings?.genres ?? [])) { book in
                    Button {
                        model.start(book: book)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(book.title).font(.headline)
                                Spacer()
                                Text("Tier \(book.tier)").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                            Text(book.note).font(.footnote)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                Button("Add a book of your own", systemImage: "plus") { adding = true }
            } header: {
                Text("Suggested next")
            } footer: {
                Text("One tier above where you're comfortable. Starting one sets aside the book you're on.")
            }
            let finished = shelf.filter { $0.status == .finished }.sorted { ($0.finished ?? .today) > ($1.finished ?? .today) }
            if !finished.isEmpty {
                Section("Finished") {
                    ForEach(finished) { book in
                        LabeledContent {
                            Text(book.feel?.label ?? "")
                        } label: {
                            Text(book.title)
                            Text("Tier \(book.tier) · \(book.finished.map { Format.day($0) } ?? "")")
                        }
                    }
                }
            }
            let before = shelf.filter { $0.status == .readBefore }
            if !before.isEmpty {
                Section("Read before Mind Track") {
                    ForEach(before) { book in LabeledContent(book.title, value: "Tier \(book.tier)") }
                }
            }
        }
        .navigationTitle("Your shelf")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $editing) { book in BookEditor(book: book) { model.save(book: $0) } }
        .sheet(isPresented: $adding) {
            BookEditor(book: nil) { book in
                for var current in model.books where current.status == .reading {
                    current.status = .abandoned
                    model.save(book: current)
                }
                var book = book
                book.started = model.today
                model.save(book: book)
            }
        }
        .sheet(item: $finishing) { book in
            PageSheet(book: book, finished: true) { _, _, feel in
                var done = book
                done.status = .finished
                done.page = book.pages
                done.finished = model.today
                done.feel = feel ?? .right
                model.save(book: done)
            }
        }
    }
}
