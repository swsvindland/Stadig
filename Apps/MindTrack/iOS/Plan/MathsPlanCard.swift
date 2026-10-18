import MindEngine
import SwiftUI
import SystemCore

/// Maths on the Plan tab: where practice is in each strand and what comes next, numeracy first.
struct MathsPlanCard: View {
    let state: StudyState

    var body: some View {
        let levels = MathsPlan.levels(state)
        let main = MathsPlan.mainStrand(state)
        let numeracy = MathsPlan.placed(.numeracy, state) ? NumeracyPlan.levels(state) : nil
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                DomainBadge(domain: .maths)
                Text("Maths").font(.headline)
                Spacer()
                if let numeracy, numeracy.overall < NumeracyPlan.weakBelow {
                    Text("Numeracy first").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(levels) { level in
                StrandRow(
                    level: level, numeracy: level.strand == .numeracy ? numeracy : nil, focus: level.strand == main,
                    placed: MathsPlan.placed(level.strand, state))
            }
            Text(footnote(levels: levels, main: main)).font(.footnote).foregroundStyle(.secondary)
            NavigationLink {
                TopicMap(state: state)
            } label: {
                Label("All topics", systemImage: "point.3.connected.trianglepath.dotted")
            }
        }
        .font(.subheadline)
        .card()
    }

    func footnote(levels: [StrandLevel], main: MathsStrand?) -> String {
        let others = levels.map(\.strand).filter { $0 != .numeracy }
        guard let main else { return "A few minutes of timed numeracy opens every maths session." }
        if others.count > 1 {
            return "Timed numeracy opens every maths session. \(main.label) gets two sessions in three, as the one you chose first."
        }
        return "Timed numeracy opens every maths session; the rest goes to \(main.label.lowercased())."
    }
}

private struct StrandRow: View {
    let level: StrandLevel
    let numeracy: NumeracyLevels?
    let focus: Bool
    let placed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(level.strand.label).font(.subheadline.weight(.semibold))
                if focus { Pill(text: "Focus", color: .accentColor) }
                Spacer()
                Text(placed ? "Working at \(level.working)" : "Placed in its first session").monospacedDigit().foregroundStyle(.secondary)
            }
            LevelMeter(level: placed ? level.working : 0)
            if let numeracy {
                HStack(spacing: 4) {
                    ForEach(NumeracySkill.allCases) { skill in
                        VStack(spacing: 2) {
                            Text("\(numeracy[skill])").font(.headline.monospacedDigit())
                                .foregroundStyle(skill == numeracy.weakest ? Color.accentColor : .primary)
                            Text(skill.short).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(skill.label), level \(numeracy[skill])")
                    }
                }
                Text(
                    "Most of each block goes to \(numeracy.weakest.label.lowercased()), the weakest. A skill moves up at four quick, right answers in five."
                )
                .font(.caption).foregroundStyle(.secondary)
            } else if level.strand != .numeracy {
                HStack {
                    Text(level.next.map { "Next: \($0)" } ?? "Everything learned").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(level.known) of \(level.total)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Ten segments, filled to a level.
struct LevelMeter: View {
    let level: Int
    var color: Color = Domain.maths.color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...10, id: \.self) { step in
                Capsule().fill(step <= level ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.secondary.opacity(0.18)))
                    .frame(height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(level) of 10")
    }
}

/// Every topic in a strand by level, and where each stands.
struct TopicMap: View {
    let state: StudyState
    @State private var strand: MathsStrand = .classic

    var body: some View {
        let known = MathsPlan.known(state.cards)
        let started = Set(state.cards.values.filter { $0.domain == .maths }.map(\.key.item))
        let next = Set(MathsPlan.frontier(state.cards).map(\.id))
        List {
            Section {
                Picker("Strand", selection: $strand) {
                    ForEach([MathsStrand.classic, .discrete]) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            ForEach(1...MathCurriculum.maxLevel, id: \.self) { level in
                let topics = MathCurriculum.topics(strand).filter { $0.level == level }
                if !topics.isEmpty {
                    Section("Level \(level)") {
                        ForEach(topics) { topic in
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
                                    Image(systemName: "lock").foregroundStyle(.secondary).accessibilityLabel("Locked")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Maths topics")
        .onAppear { if let main = MathsPlan.mainStrand(state) { strand = main } }
    }
}
