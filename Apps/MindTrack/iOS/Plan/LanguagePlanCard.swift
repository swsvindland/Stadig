import MindEngine
import SwiftUI
import SystemCore

/// A language on the Plan tab: its four skills, what comes next (new words, the next dialogue, a
/// reader at its level) and the real-world benchmark.
struct LanguagePlanCard: View {
    @Environment(AppModel.self) private var model
    let summary: LanguageSummary
    let state: StudyState

    var domain: Domain { summary.domain }
    var language: Language { domain.language ?? .japanese }

    /// New words a session and the week's reviews, from the pacing sessions use, so the card says
    /// what they'll teach.
    var pace: (count: Int, reason: String?, dueThisWeek: Int) { LanguagePlan.pace(domain, state: state, reviewWeek: state.phase.isReview) }

    var body: some View {
        let retention = summary.retention
        let pace = self.pace
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                DomainBadge(domain: domain)
                Text(domain.label).font(.headline)
                Spacer()
                Text("\(summary.wordsLearned) words in").font(.subheadline).foregroundStyle(.secondary)
            }
            if model.catalogs.deck(for: domain) == nil {
                Text("The \(domain.label) catalog isn't installed in this build.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                SkillLevels(domain: domain, state: state, compact: true)
                if summary.mode == .maintenance {
                    LabeledContent("Maintenance", value: "Reviews only")
                    LabeledContent("Due this week", value: "\(pace.dueThisWeek)")
                    LabeledContent("Recall on reviews", value: retention.map(Format.percent) ?? "Not enough yet")
                } else {
                    LabeledContent("New words a session", value: "\(pace.count)")
                    LabeledContent("Recall on reviews", value: retention.map(Format.percent) ?? "Not enough yet")
                    if let reason = pace.reason { Text(reason).font(.footnote).foregroundStyle(.secondary) }
                    if let dialogue = nextDialogue {
                        LabeledContent("Next dialogue", value: dialogue.title)
                    }
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
                if let reader = nextReader {
                    LabeledContent("A reader at your level", value: reader.title)
                }
                Text(benchmark).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .card()
    }

    var nextDialogue: Dialogue? {
        let known = state.cards.values.filter { $0.domain == domain && $0.memory != nil && !$0.key.isKana }.count
        guard known >= 15 else { return nil }
        let level = Dialogues.level(frontier: LanguagePlan.frontier(state.tests, language), known: known)
        return Dialogues.next(language, level: level, practised: Dialogues.practised(language, sessions: state.sessions))
    }

    var nextReader: GradedReader? {
        guard GradedReaders.current(language, books: state.books) == nil else { return nil }
        let words = state.latest(.vocabulary, in: domain).map { Int($0.score) }
        return GradedReaders.suggestions(language, books: state.books, words: words, count: 1).first
    }

    /// The real-world test, when it's due.
    var benchmark: String {
        let last = state.tests.filter { $0.test.selfRated && $0.domain == domain }.map(\.day).max()
        let since = last.map { $0.days(until: state.today) }
        if state.phase.isReview {
            return "Review week: watch an episode in \(domain.label) without subtitles, just for fun, and note how much you followed."
        }
        if let since, since < 28 {
            return "Real-world check: last logged \(since == 0 ? "today" : "\(since) days ago"). The next review week is a good time for another."
        }
        return "Real-world check: an episode without subtitles or a real conversation now and then, logged on Progress. Never scored."
    }

    var upcomingWords: [Word] {
        guard let deck = model.catalogs.deck(for: domain), let language = domain.language else { return [] }
        let items = LanguagePlan.next(
            count: 8, cards: Set(state.cards.keys), deck: deck, readsKana: language == .japanese ? state.settings.readsKana : true,
            frontier: LanguagePlan.frontier(state.tests, language))
        return items.compactMap { item in
            switch item {
            case .teach(let word): word
            case .probe, .kana: nil
            }
        }
    }
}
