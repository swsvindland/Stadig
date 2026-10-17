import SwiftUI
import MindEngine
import SystemCore

/// A minute of setup, then the first session finds the level: the onboarding is the first session.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var settings = MindSettings(onboardedAt: nil)
    @State private var read: Set<String> = []
    @State private var hard: Set<String> = []

    var pages: [Int] { settings.has(.reading) ? [0, 1, 2, 3, 4, 5] : [0, 1, 2, 3, 5] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch page {
                        case 0: welcome
                        case 1: domains
                        case 2: schedule
                        case 3: levels
                        case 4: books
                        default: ready
                        }
                    }
                    .padding(24)
                    .readableWidth(600)
                }
                BottomBar {
                    HStack(spacing: 12) {
                        if page > 0 {
                            Button {
                                withAnimation { page = pages[max(0, (pages.firstIndex(of: page) ?? 0) - 1)] }
                            } label: {
                                Text("Back").frame(maxWidth: .infinity)
                            }
                            .secondaryAction()
                            .controlSize(.large)
                        }
                        Button {
                            if page == 5 { finish() } else { withAnimation { page = pages[min(pages.count - 1, (pages.firstIndex(of: page) ?? 0) + 1)] } }
                        } label: {
                            Text(page == 5 ? "Start the first session" : page == 0 ? "Set up" : "Next").font(.headline).frame(maxWidth: .infinity)
                        }
                        .primaryAction()
                        .controlSize(.large)
                        .disabled(page == 1 && settings.domains.isEmpty)
                    }
                }
            }
            .background(.pageBackground)
        }
    }

    var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "brain.head.profile").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Mind Track").font(.largeTitle.bold())
            Text("Lift Track for the mind: focused 25-minute sessions that find your level, then train it.").font(.title3)
            VStack(alignment: .leading, spacing: 12) {
                Label("The first sessions find where you are in each subject", systemImage: "scope")
                Label("Something new only once the last thing has stuck", systemImage: "stairs")
                Label("Reviews come back just before you'd forget", systemImage: "arrow.triangle.2.circlepath")
                Label("Intelligence and Wisdom move only on real tests, never on time spent", systemImage: "gauge.with.dots.needle.67percent")
            }
            .font(.body)
            .padding(.top, 8)
        }
    }

    var domains: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What do you want to train?").font(.title.bold())
            ForEach(Domain.allCases) { domain in
                Button {
                    if settings.has(domain) { settings.domains.removeAll { $0 == domain } } else { settings.domains = (settings.domains + [domain]).sorted() }
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        DomainBadge(domain: domain, size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(domain.label).font(.headline)
                            Text(domain.pitch).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: settings.has(domain) ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(settings.has(domain) ? Color.accentColor : .secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(settings.has(domain) ? .isSelected : [])
            }
        }
    }

    var schedule: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("When do you study?").font(.title.bold())
            Text("Subjects rotate across the week like a training split. Reviews from every subject open each session.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Stepper(value: Binding(get: { settings.schedule.daysPerWeek }, set: { settings.schedule = StudySchedule(daysPerWeek: $0, minutes: settings.schedule.minutes) }),
                        in: 1...7) {
                    LabeledContent("Days a week", value: "\(settings.schedule.daysPerWeek)")
                }
                Picker("Session length", selection: Binding(get: { settings.schedule.minutes }, set: { settings.schedule.minutes = $0 })) {
                    ForEach(StudySchedule.sessionOptions, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .card()
            WeekPreview(settings: settings)
        }
    }

    var levels: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A head start").font(.title.bold())
            Text("Two quick answers so the first session starts in the right place. It finds the rest itself.").foregroundStyle(.secondary)
            if settings.has(.japanese) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Can you read hiragana and katakana?", systemImage: Domain.japanese.symbol).font(.headline)
                    Picker("Kana", selection: Binding(get: { settings.readsKana ?? true }, set: { settings.readsKana = $0 })) {
                        Text("Yes").tag(true)
                        Text("Not yet").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text(settings.readsKana == false ? "You'll start with hiragana; words follow once it's in." : "You'll start with a word test to find your vocabulary.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .card()
            }
            if settings.has(.maths) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("How far did you get with maths?", systemImage: Domain.maths.symbol).font(.headline)
                    Picker("Maths", selection: $settings.mathsBackground) {
                        ForEach(MathsBackground.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Text("Long ago is fine: the placement steps down until it finds solid ground.").font(.footnote).foregroundStyle(.secondary)
                }
                .card()
            }
            if !settings.has(.japanese) && !settings.has(.maths) {
                Text("Nothing to ask here.").foregroundStyle(.secondary)
            }
        }
        .onAppear { if settings.readsKana == nil { settings.readsKana = true } }
    }

    var books: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What have you read?").font(.title.bold())
            Text("Tick books you've finished; tap twice for one that was hard going. The ladder starts one step above.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Genres you enjoy").font(.headline)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Genre.allCases) { genre in
                        let on = settings.genres.contains(genre)
                        Button {
                            if on { settings.genres.removeAll { $0 == genre } } else { settings.genres.append(genre) }
                        } label: {
                            Text(genre.label).font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 7)
                                .background(on ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: .capsule)
                                .foregroundStyle(on ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .card()
            ForEach(ReadingLadder.standard.tiers, id: \.tier) { tier in
                let books = ReadingLadder.standard.books.filter { $0.tier == tier.tier }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tier \(tier.tier) · \(tier.label)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(books) { book in
                        Button {
                            if hard.contains(book.id) { hard.remove(book.id); read.remove(book.id) }
                            else if read.contains(book.id) { hard.insert(book.id) }
                            else { read.insert(book.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(book.title).font(.body)
                                    Text(book.author).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if hard.contains(book.id) { Pill(text: "Hard going", color: .orange) }
                                Image(systemName: read.contains(book.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(read.contains(book.id) ? Color.accentColor : .secondary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(padding: 14)
            }
        }
    }

    var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your first session").font(.largeTitle.bold())
            Text("About \(settings.schedule.minutes) minutes to find your level, then the first new material. Answer honestly: “Don't know” is always better than a guess.")
                .font(.title3)
            VStack(alignment: .leading, spacing: 10) {
                if settings.has(.japanese) {
                    Label(settings.readsKana == false ? "Japanese: your first hiragana" : "Japanese: words from common to rare", systemImage: Domain.japanese.symbol)
                }
                if settings.has(.maths) { Label("Maths: about a dozen problems", systemImage: Domain.maths.symbol) }
                if settings.has(.writing) { Label("Writing: one item for each skill", systemImage: Domain.writing.symbol) }
                if settings.has(.reading) {
                    Label("Reading: your ladder starts at tier \(ReadingPlan.targetTier(shelf))", systemImage: Domain.reading.symbol)
                }
            }
            .card()
        }
    }

    var shelf: [Book] {
        ReadingLadder.standard.books.filter { read.contains($0.id) }.map { book in
            var finished = book.book(status: .readBefore)
            if hard.contains(book.id) { finished.feel = .hard }
            return finished
        }
    }

    func finish() {
        if !settings.has(.japanese) { settings.readsKana = nil }
        model.completeOnboarding(settings, booksRead: shelf)
    }
}

/// The week the split makes, previewed.
struct WeekPreview: View {
    let settings: MindSettings

    var body: some View {
        let monday = Day.today.startOfWeek
        let week = Split.week(starting: monday, settings: settings)
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let day = monday.adding(days: offset)
                VStack(spacing: 6) {
                    Text(day.weekday.short).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    VStack(spacing: 3) {
                        ForEach(week[day] ?? [], id: \.self) { DomainBadge(domain: $0, size: 26) }
                        if (week[day] ?? []).isEmpty {
                            Circle().fill(Color.secondary.opacity(0.15)).frame(width: 26, height: 26)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .card(padding: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Weekday.allCases.compactMap { weekday in
            let day = monday.adding(days: weekday.rawValue - 1)
            return week[day].map { "\(weekday.name): \($0.map(\.label).joined(separator: " and "))" }
        }.joined(separator: ". "))
    }
}
