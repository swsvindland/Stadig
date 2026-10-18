import Charts
import SwiftUI
import MindEngine
import SystemCore

/// A language on the Progress tab: its four skills like separate lifts, vocabulary, the graded
/// readers and the real thing (episodes and conversations, logged but never scored).
struct LanguageProgress: View {
    @Environment(AppModel.self) private var model
    let summary: LanguageSummary
    let state: StudyState

    var language: Language { summary.domain.language ?? .japanese }

    var body: some View {
        let series = Analyst.series(summary.domain, state: state)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                DomainBadge(domain: summary.domain)
                Text(summary.domain.label).font(.headline)
                Spacer()
                if summary.mode == .maintenance { Pill(text: "Maintenance", color: .secondary) }
            }
            SkillLevels(domain: summary.domain, state: state)
            if let latest = series.last, series.count >= 2 || LanguageSkills.levels(summary.domain, tests: state.tests).count >= 3 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(summary.domain.label) score").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(latest.score.rounded()))").font(.title3.bold().monospacedDigit())
                    }
                    Text("The four skills together, listening and speaking counting most. Only the tests move it.")
                        .font(.caption).foregroundStyle(.secondary)
                    ScoreChart(points: series.map { ($0.day.date(), $0.score) }, color: summary.domain.color)
                }
            }
            Divider()
            if let vocabulary = summary.vocabulary {
                VStack(alignment: .leading, spacing: 2) {
                    Text("About \(Int(vocabulary.score).formatted()) words").font(.title3.bold())
                    Text("\(Int(vocabulary.detail["low"] ?? 0).formatted())–\(Int(vocabulary.detail["high"] ?? 0).formatted()) · \(LanguageTests.level(words: vocabulary.score, language: language))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else if summary.domain == .japanese, state.settings.readsKana == false {
                Text("\(summary.kanaLearned) of \(KanaTable.all.count) kana in. The word test comes once hiragana is.").foregroundStyle(.secondary)
            } else {
                Text("The word test comes in the first session.").foregroundStyle(.secondary)
            }
            LabeledContent("Words learned here", value: "\(summary.wordsLearned)")
            if let retention = summary.retention { LabeledContent("Recall on reviews", value: Format.percent(retention)) }
            Divider()
            ReadersSection(language: language, state: state)
            Divider()
            RealWorldSection(language: language, state: state)
        }
        .font(.subheadline)
        .card()
    }
}

/// The four skills side by side, each with its own level.
struct SkillLevels: View {
    let domain: Domain
    let state: StudyState
    var compact = false

    var body: some View {
        let levels = LanguageSkills.levels(domain, tests: state.tests)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(LanguageSkill.allCases) { skill in
                SkillTile(skill: skill, level: levels[skill], pending: pending(skill), compact: compact)
            }
        }
    }

    /// What a skill without a level is waiting for.
    func pending(_ skill: LanguageSkill) -> String {
        if skill == .speaking && !state.settings.speaking { return "Speaking is off" }
        let words = Int(state.latest(.vocabulary, in: domain)?.score ?? 0)
        if state.settings.mode(domain) == .focus, words >= LanguageSkills.measuredFrom { return "Measured next session" }
        return "At the first check-in"
    }
}

private struct SkillTile: View {
    let skill: LanguageSkill
    let level: SkillLevel?
    let pending: String
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.caption)
                Text(skill.label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            if let level {
                Text("Level \(level.level)").font((compact ? Font.headline : .title3).bold())
                Text(level.label).font(.caption)
                if !compact {
                    Text("~\(level.words.formatted()) words' reach · \(level.test.date.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("—").font((compact ? Font.headline : .title3).bold())
                Text(pending).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.insetBackground, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    var symbol: String {
        switch skill {
        case .listening: "ear"
        case .speaking: "mic"
        case .reading: "text.book.closed"
        case .writing: "pencil"
        }
    }
}

private struct ScoreChart: View {
    let points: [(date: Date, value: Double)]
    let color: Color

    var body: some View {
        if points.count >= 2 {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value("Score", point.value)).foregroundStyle(color)
                    PointMark(x: .value("Date", point.date), y: .value("Score", point.value)).foregroundStyle(color)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 120)
            .accessibilityLabel("Score over time: \(points.map { "\(Int($0.value.rounded()))" }.joined(separator: ", "))")
        }
    }
}

/// Episodes without subtitles and real conversations: the real-world benchmark. Logged and shown,
/// never scored: the tests measure, these are how real use starts to feel.
struct RealWorldSection: View {
    @Environment(AppModel.self) private var model
    let language: Language
    let state: StudyState

    var body: some View {
        let logs = state.tests.filter { $0.test.selfRated && $0.domain == language.domain }.sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("The real thing", systemImage: "person.2.wave.2").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Log one") { model.episodeLanguage = language }.buttonStyle(.borderless)
            }
            if logs.isEmpty {
                Text("The benchmark that matters: an episode without subtitles, or a real conversation. Now and then, try one and note how much you followed. It's never scored.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(logs.prefix(4)) { log in
                    HStack(spacing: 8) {
                        Image(systemName: log.test == .episode ? "tv" : "bubble.left.and.bubble.right").foregroundStyle(.secondary).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(log.test == .episode ? "Episode, no subtitles" : "Conversation").font(.caption.weight(.medium))
                            Text(log.date.formatted(.dateTime.day().month(.abbreviated).year())).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Self.rating(log)).font(.caption)
                        FollowedDots(rating: Int(log.detail["rating"] ?? log.score * 3))
                    }
                }
                if logs.count > 4 { Text("\(logs.count) logged so far").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }

    static func rating(_ log: TestResult) -> String {
        ["Lost", "Caught bits", "Followed most", "Followed nearly all"][min(3, max(0, Int(log.detail["rating"] ?? (log.score * 3).rounded())))]
    }
}

private struct FollowedDots: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(i < rating ? Color.accentColor : Color.secondary.opacity(0.25)).frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}
