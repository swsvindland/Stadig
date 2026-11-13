import Charts
import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// The filters the Library screen offers, as the person set them.
struct LibraryFilters: Hashable {
    var kind: ExerciseKind?
    var pattern: MovementPattern?
    var equipment: Equipment?
    var muscle: Muscle?
    var easyOn: Joint?
    var inMyGym = false
    var safeWithInjuries = false

    var isEmpty: Bool { self == LibraryFilters() }
}

/// Every exercise, searchable and filterable, beside the one chosen: what it is, what it costs,
/// what could replace it, and the person's own history with it. The list is the family's: a page
/// header, a search field and the filters as chips, the exercises as rows on the card fill; the
/// exercise beside it is the phone's exercise page.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filters = LibraryFilters()
    @State private var selection: Exercise.ID?
    @State private var results: [Exercise] = []
    /// The search field has the keyboard: ⌘F gives it it.
    @FocusState private var searching: Bool

    /// What the list depends on: a change to any of it filters again.
    private struct Key: Hashable {
        var query: String
        var filters: LibraryFilters
        var gym: Gym
        var injuries: [Injury]
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                list
                    .frame(width: Platform.isMac ? 320 : 360)
                Rectangle().fill(Ink.hairline).frame(width: 1).ignoresSafeArea()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(.pageBackground)
            .navigationTitle("Library")
            .ownHeader()
            .toolbar {
                if let selection, let exercise = model.catalog[selection] {
                    // A quiet action in the text's colour, as the exercise page has it, not the accent.
                    ToolbarItem(placement: .primaryAction) { AsideButton(exercise: exercise).tint(Ink.text) }
                }
            }
            .sessionResumeToolbar()
        }
        .accessibilityIdentifier("library.screen")
        .task(id: Key(query: query, filters: filters, gym: model.gym, injuries: model.analysis?.life.injuries ?? [])) { filter() }
        .onChange(of: model.libraryFocus, initial: true) { _, focus in
            guard let focus else { return }
            // Shown whatever the filters were: they'd otherwise hide what was asked for.
            query = ""
            filters = LibraryFilters()
            selection = focus
            model.libraryFocus = nil
        }
        .onChange(of: model.searchRequested, initial: true) { _, requested in
            guard requested, model.tab == .library else { return }
            searching = true
            model.searchRequested = false
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selection, let exercise = model.catalog[selection] {
            ExerciseDetailView(exercise: exercise, inLibrary: true) { self.selection = $0 }
                .id(exercise.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "books.vertical").font(.title).foregroundStyle(Ink.text3)
                Text("Choose an exercise").font(.headline).foregroundStyle(Ink.text)
                Text("Its cue, muscles and joints, what could replace it, and your history with it.")
                    .font(.subheadline).foregroundStyle(Ink.text2).multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var list: some View {
        let inProgram = model.currentMesocycle?.exerciseIDs ?? []
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                PageHeader(eyebrow: "\(results.count) of \(model.catalog.all.count) exercises", title: "Library")
                InkSearchField(text: $query, prompt: "Exercises, muscles, equipment", identifier: "library.search")
                    .focused($searching)
                chips
            }
            .padding(.horizontal, 16)
            List(selection: $selection) {
                ForEach(results) { exercise in
                    LibraryRow(
                        exercise: exercise, inProgram: inProgram.contains(exercise.id), setAside: model.settings.avoid.contains(exercise.id),
                        ruledOut: model.analysis?.life.injuries.contains { $0.excludes(exercise) } ?? false, selected: selection == exercise.id
                    )
                    .tag(exercise.id)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                    .contextMenu { rowMenu(exercise) }
                    .accessibilityIdentifier("library.row")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 44)
            .overlay {
                if results.isEmpty {
                    Text(query.isEmpty ? "Nothing matches these filters." : "Nothing called \u{201C}\(query)\u{201D}.")
                        .font(.subheadline).foregroundStyle(Ink.text2).padding(24)
                }
            }
        }
    }

    /// Every filter as a chip: a menu of its choices, filled once one is picked, and the two toggles.
    private var chips: some View {
        FlowLayout(spacing: 6) {
            FilterChip(title: "Kind", value: filters.kind?.label) {
                Picker("Kind", selection: $filters.kind) {
                    Text("Every kind").tag(ExerciseKind?.none)
                    ForEach(ExerciseKind.allCases, id: \.self) { Text($0.label).tag(ExerciseKind?.some($0)) }
                }
            }
            FilterChip(title: "Movement", value: filters.pattern?.label) {
                Picker("Movement", selection: $filters.pattern) {
                    Text("Any movement").tag(MovementPattern?.none)
                    ForEach(ExerciseFilter.patterns(in: model.catalog.all, kind: filters.kind)) { Text($0.label).tag(MovementPattern?.some($0)) }
                }
            }
            FilterChip(title: "Equipment", value: filters.equipment?.label) {
                Picker("Equipment", selection: $filters.equipment) {
                    Text("Any equipment").tag(Equipment?.none)
                    ForEach(ExerciseFilter.equipment(in: model.catalog.all, kind: filters.kind)) { Text($0.label).tag(Equipment?.some($0)) }
                }
            }
            FilterChip(title: "Muscle", value: filters.muscle?.label) {
                Picker("Muscle", selection: $filters.muscle) {
                    Text("Any muscle").tag(Muscle?.none)
                    ForEach(Muscle.allCases) { Text($0.label).tag(Muscle?.some($0)) }
                }
            }
            FilterChip(title: "Easy on", value: filters.easyOn.map { "Easy on the \($0.label.lowercased())" }) {
                Picker("Easy on", selection: $filters.easyOn) {
                    Text("Any joint").tag(Joint?.none)
                    ForEach(Joint.allCases) { Text($0.label).tag(Joint?.some($0)) }
                }
            }
            ToggleChip(title: "In my gym", on: $filters.inMyGym)
            ToggleChip(title: "Safe with my injuries", on: $filters.safeWithInjuries)
            if !filters.isEmpty {
                Button("Clear") { filters = LibraryFilters() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                    .frame(minHeight: 30)
                    .accessibilityLabel("Clear the filters")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.filter")
    }

    @ViewBuilder
    private func rowMenu(_ exercise: Exercise) -> some View {
        if model.settings.avoid.contains(exercise.id) {
            Button("Allow Back", systemImage: "arrow.uturn.backward") { model.setAside(exercise.id, false) }
        } else if exercise.kind == .strength {
            Button("Set Aside", systemImage: "nosign") { model.setAside(exercise.id, true) }
        }
        Button("Show Substitutes", systemImage: "arrow.triangle.2.circlepath") { selection = exercise.id }
    }

    private func filter() {
        let filter = ExerciseFilter(
            kind: filters.kind, pattern: filters.pattern, equipment: filters.equipment, muscle: filters.muscle, easyOn: filters.easyOn,
            availability: filters.inMyGym ? model.gym.availability : nil,
            injuries: filters.safeWithInjuries ? model.analysis?.life.injuries ?? [] : nil)
        results = filter.apply(to: model.catalog.all, query: query)
    }
}

/// A filter as the family's chip: its name, or what's picked, with a chevron; a menu of the choices.
private struct FilterChip<Choices: View>: View {
    let title: String
    let value: String?
    @ViewBuilder let choices: Choices

    var body: some View {
        Menu {
            choices
        } label: {
            HStack(spacing: 4) {
                Text(value ?? title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(value == nil ? Ink.text2 : Color.accentColor)
            .padding(.horizontal, 11)
            .frame(minHeight: 30)
            .background(value == nil ? Ink.raised : Color.accentColor.opacity(0.18), in: .capsule)
            .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(value.map { "\(title): \($0)" } ?? title)
    }
}

/// A filter that's on or off, as a chip filled when it's on.
private struct ToggleChip: View {
    let title: String
    @Binding var on: Bool

    var body: some View {
        Button {
            on.toggle()
        } label: {
            HStack(spacing: 4) {
                if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(title).lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(on ? Color.accentColor : Ink.text2)
            .padding(.horizontal, 11)
            .frame(minHeight: 30)
            .background(on ? Color.accentColor.opacity(0.18) : Ink.raised, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .fixedSize()
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// An exercise in the list: its name, what it is, and whether it's in the program, set aside, or
/// ruled out by an injury. The one chosen is lifted onto the card fill with the accent's edge.
private struct LibraryRow: View {
    let exercise: Exercise
    let inProgram: Bool
    let setAside: Bool
    let ruledOut: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.callout.weight(.semibold)).foregroundStyle(setAside ? Ink.text3 : Ink.text).lineLimit(1)
                Text(exercise.kindLine).font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
            }
            Spacer(minLength: 4)
            if inProgram {
                Text("In block").eyebrow(.accentColor).help("In this block").accessibilityLabel("In this block")
            }
            if ruledOut {
                Image(systemName: "bandage").font(.caption).foregroundStyle(Ink.ok).help("Ruled out by an injury")
                    .accessibilityLabel("Ruled out by an injury")
            }
            if setAside {
                Image(systemName: "nosign").font(.caption).foregroundStyle(Ink.text3).help("Set aside").accessibilityLabel("Set aside")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected ? Color.cardBackground : .clear, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
            }
        }
        .contentShape(.rect)
    }
}

/// Set aside, or allow back: the exercise page's quiet action.
private struct AsideButton: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise

    var body: some View {
        if model.settings.avoid.contains(exercise.id) {
            Button("Allow Back") { model.setAside(exercise.id, false) }
                .help("Let the program use it again")
                .accessibilityIdentifier("library.allowBack")
        } else if exercise.kind == .strength {
            Button("Set Aside") { model.setAside(exercise.id, true) }
                .help("Never programme it; today's session swaps it out")
                .accessibilityIdentifier("library.setAside")
        }
    }
}

/// An exercise pushed onto a narrow window's stack, which has no Library tab to send it to. A
/// substitute picked in it is pushed after it, as rows with a chevron are on the iPhone.
struct PushedExerciseDetail: View {
    @Environment(AppModel.self) private var model
    let exerciseID: String
    @State private var next: String?

    var body: some View {
        ExerciseDetailView(exercise: model.catalog.resolve(exerciseID)) { next = $0 }
            .navigationDestination(item: $next) { id in PushedExerciseDetail(exerciseID: id) }
    }
}

/// One exercise in full, as the design draws it: what it is and how to do it, the estimated one-rep
/// max as the hero with its line and one sentence about it, the score on the levels' ruler, the best
/// sets, what could replace it, and Set aside as a quiet action. Below, where it's in the block, an
/// injury's say, and the library's facts.
struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let exercise: Exercise
    /// In the wide Library's pane, whose bar has Set aside and no title: the page sets its own.
    var inLibrary = false
    /// Shows another exercise in the library: a substitute picked here.
    let select: (String) -> Void
    @State private var shown: ExerciseDetailContent?
    /// The design's 30 points, growing with the text size like the words round it.
    @ScaledMetric(relativeTo: .title) private var nameSize: CGFloat = 30

    /// What the screen's numbers depend on: a change to any of it works them out again.
    private struct Key: Hashable {
        var sessions: Int
        var unit: WeightUnit
        var gym: Gym
        var injuries: [Injury]
        var avoid: Set<String>
        var bodyweightKg: Double?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                // Set aside or an injury's say matter before anything else; where it is in the block
                // is a quiet line at the foot.
                if isAside || !injuries.isEmpty { status }
                if sizeClass.isWide {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 12) {
                            estimate
                            bestSets
                        }
                        VStack(spacing: 12) {
                            substitutes
                            if !isAside && injuries.isEmpty { status }
                            ExerciseFacts(exercise: exercise, showsCueAndMuscles: false).card()
                        }
                    }
                } else {
                    estimate
                    bestSets
                    substitutes
                    if !isAside && injuries.isEmpty { status }
                    ExerciseFacts(exercise: exercise, showsCueAndMuscles: false).card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.pageBackground)
        .modifier(DetailChrome(title: exercise.name, inLibrary: inLibrary, wide: sizeClass.isWide) { asideButton.tint(Ink.text) })
        .task(id: key) { shown = ExerciseDetailContent(exercise: exercise, model: model) }
        .accessibilityIdentifier("library.detail")
    }

    private var key: Key {
        Key(
            sessions: model.sessions.count, unit: model.gym.unit, gym: model.gym, injuries: model.analysis?.life.injuries ?? [],
            avoid: model.settings.avoid, bodyweightKg: model.analysis?.strength.bodyweightKg)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow).eyebrow(.accentColor)
            Text(exercise.name)
                .font(.system(size: nameSize, weight: .bold)).tracking(-0.8)
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !exercise.cue.isEmpty {
                Text(exercise.cue).font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
            }
            if !exercise.muscles.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(exercise.muscles.sorted { $0.weight > $1.weight }, id: \.muscle) { share in
                        MuscleChip(label: share.muscle.label, primary: share.weight >= 1)
                    }
                }
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Muscles worked")
                .accessibilityValue(exercise.muscles.sorted { $0.weight > $1.weight }.map(\.muscle.label).joined(separator: ", "))
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    /// "Main lift · Barbell" when the block uses it, else what it is: "Squat · Barbell", "Mobility drills · Band".
    private var eyebrow: String {
        let roles = Set(model.currentMesocycle?.days.flatMap(\.strengthSlots).filter { $0.exerciseID == exercise.id }.map(\.role) ?? [])
        let first: String =
            if roles.contains(.main) { "Main lift" } else if roles.contains(.accessory) { "Accessory" } else if exercise.kind == .strength {
                exercise.pattern.label
            } else { exercise.kind.label }
        return "\(first) · \(exercise.equipment.label)"
    }

    @ViewBuilder
    private var asideButton: some View {
        if model.settings.avoid.contains(exercise.id) {
            Button(sizeClass.isWide ? "Allow Back" : "Allow back") { model.setAside(exercise.id, false) }
                .help("Let the program use it again")
                .accessibilityIdentifier("library.allowBack")
        } else if exercise.kind == .strength {
            Button(sizeClass.isWide ? "Set Aside" : "Set aside") { model.setAside(exercise.id, true) }
                .help("Never programme it; today's session swaps it out")
                .accessibilityIdentifier("library.setAside")
        }
    }

    private var isAside: Bool { model.settings.avoid.contains(exercise.id) }

    /// The injuries that have a say on it.
    private var injuries: [(LifeModePeriod, Injury)] {
        model.activeInjuries.compactMap { period -> (LifeModePeriod, Injury)? in
            if case .injury(let injury) = period.kind, injury.affects(exercise) || injury.removed.contains(exercise.id) { return (period, injury) }
            return nil
        }
    }

    /// Set aside, ruled out by an injury, or in this block, with what to do about it.
    @ViewBuilder
    private var status: some View {
        let days = model.currentMesocycle?.days.filter { $0.strengthSlots.contains { $0.exerciseID == exercise.id } } ?? []
        let injuries = self.injuries
        if !days.isEmpty || model.settings.avoid.contains(exercise.id) || !injuries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !days.isEmpty {
                    Label("In this block on \(days.map(\.name).joined(separator: ", ")).", systemImage: "calendar")
                }
                if model.settings.avoid.contains(exercise.id) {
                    Label(
                        "Set aside: new blocks never use it, and today's session swaps it for something else.", systemImage: "nosign")
                }
                ForEach(injuries, id: \.0.id) { period, injury in
                    let out = injury.excludes(exercise)
                    HStack(alignment: .firstTextBaseline) {
                        Label(
                            out
                                ? "Ruled out for now by your injury (\(injury.summary))."
                                : "Allowed despite your injury (\(injury.summary)).", systemImage: "bandage")
                        Spacer()
                        Button(out ? "Allow It Anyway" : "Rule It Out") { model.toggleInjuryOverride(for: exercise, in: period.id) }
                            .secondaryAction()
                            .controlSize(.small)
                            .accessibilityIdentifier("library.injuryOverride")
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(Ink.text2)
            .card(padding: 14, radius: 18)
        }
    }

    // MARK: The estimate

    /// The estimated one-rep max as the hero, its line, one sentence about it, and the score on the
    /// levels' ruler. Without an estimate (never done, or timed work), what will show here.
    @ViewBuilder
    private var estimate: some View {
        if let shown {
            if let current = shown.record.current {
                let unit = model.gym.unit
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Est. 1RM").eyebrow()
                            // Whole units: an estimate isn't good to a tenth, and the hero reads at a glance.
                            Measure(value: Format.number(unit.fromKilograms(current), digits: 0), unit: unit.symbol, size: 68, weight: .heavy)
                                .accessibilityLabel("Estimated one-rep max \(Format.weight(current, unit: unit))")
                        }
                        Spacer(minLength: 0)
                        if shown.record.movement != nil {
                            VStack(alignment: .trailing, spacing: 2) {
                                sentence(shown)
                                ratio(shown)
                            }
                            .padding(.bottom, 4)
                            .layoutPriority(1)
                        }
                    }
                    if shown.record.movement == nil {
                        VStack(alignment: .leading, spacing: 2) {
                            sentence(shown)
                            ratio(shown)
                        }
                    }
                    if shown.record.trend.count >= 2 {
                        EstimateLine(points: shown.points, domain: shown.domain)
                            .accessibilityLabel("\(exercise.name) estimated one-rep max over time")
                            .accessibilityValue(shown.sentence ?? "")
                        HStack {
                            ForEach(Array(shown.scale.enumerated()), id: \.offset) { index, label in
                                if index > 0 { Spacer() }
                                Text(label)
                            }
                        }
                        .font(.system(size: 10, weight: .semibold)).textCase(.uppercase).tracking(0.6).foregroundStyle(Ink.text3)
                        .accessibilityHidden(true)
                    }
                    if let score = shown.score {
                        Rectangle().fill(Ink.hairline).frame(height: 1).padding(.vertical, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("Score \(Int(score.rounded()))").font(.headline).foregroundStyle(Ink.text)
                                Text("· \(StrengthStandards.level(for: score))").font(.headline.weight(.medium)).foregroundStyle(Ink.text3)
                                Spacer(minLength: 8)
                                if let next = LevelRuler.next(score) { Text(next).font(.caption).foregroundStyle(Ink.text2) }
                            }
                            .accessibilityElement(children: .combine)
                            LevelRuler(score: score, height: 14, short: true)
                        }
                    }
                }
                .card(padding: 16)
                .accessibilityIdentifier("library.estimate")
            } else if shown.record.isEmpty {
                Text("Not done yet. Once it's in a session, its sets and estimated one-rep max show here.")
                    .font(.subheadline).foregroundStyle(Ink.text2)
                    .card()
            }
        }
    }

    private func sentence(_ shown: ExerciseDetailContent) -> some View {
        Text(shown.sentence ?? "")
            .font(.headline)
            .foregroundStyle(shown.movementColor)
            .multilineTextAlignment(shown.record.movement == nil ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func ratio(_ shown: ExerciseDetailContent) -> some View {
        if let ratio = shown.bodyweightRatio {
            Text("\(ratio.formatted(.number.precision(.fractionLength(2)))) × bodyweight").font(.caption).foregroundStyle(Ink.text2)
        }
    }

    // MARK: Best sets

    @ViewBuilder
    private var bestSets: some View {
        if let record = shown?.record, !record.isEmpty {
            let unit = model.gym.unit
            VStack(alignment: .leading, spacing: 0) {
                SectionEyebrow("Best sets", detail: sessionsLine(record))
                    .padding(.bottom, 2)
                ForEach(Array(record.bestSets.enumerated()), id: \.element.set.id) { index, best in
                    if index > 0 { Rectangle().fill(Ink.hairline).frame(height: 1) }
                    HStack(spacing: 8) {
                        SetValue(
                            load: best.set.loadKg, reps: best.set.reps, seconds: best.set.seconds, plus: false, exercise: exercise, unit: unit,
                            quiet: false)
                        Spacer()
                        Text(Format.day(Day(best.set.date), style: .dateTime.day().month(.abbreviated))).font(.caption)
                            .foregroundStyle(Ink.text3)
                    }
                    .frame(minHeight: 36)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
        }
    }

    /// "12 sessions · last 4 Nov".
    private func sessionsLine(_ record: ExerciseRecord) -> String {
        let count = "\(record.sessions) \(record.sessions == 1 ? "session" : "sessions")"
        guard let last = record.lastDone else { return count }
        return "\(count) · last \(Format.day(last, style: .dateTime.month(.abbreviated).day()))"
    }

    // MARK: Substitutes

    @ViewBuilder
    private var substitutes: some View {
        if let options = shown?.substitutes {
            VStack(alignment: .leading, spacing: 8) {
                Text("Substitutes").eyebrow().padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Substitutes in your gym")
                if options.isEmpty {
                    Text("Nothing else in your gym trains the same thing.").font(.subheadline).foregroundStyle(Ink.text2)
                        .padding(.horizontal, 4)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(options) { option in
                                Button {
                                    select(option.id)
                                } label: {
                                    Text(option.name)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Ink.text)
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 36)
                                        .background(.cardBackground, in: .capsule)
                                        // A fingertip's height to hit, round a slimmer chip.
                                        .frame(minHeight: 44)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .hoverHighlight()
                                .accessibilityHint(option.kindLine)
                                .accessibilityIdentifier("library.substitute")
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The exercise page's bar: the name set large on the page itself, so the bar keeps only back and
/// Set aside (and the tab bar goes, as on the design's detail screens). In the wide Library the
/// Library's own bar has Set aside.
private struct DetailChrome<Aside: View>: ViewModifier {
    let title: String
    let inLibrary: Bool
    let wide: Bool
    @ViewBuilder let aside: Aside

    func body(content: Content) -> some View {
        if inLibrary {
            content
        } else {
            content
                .navigationTitle(title)
                .inlineTitle()
                #if os(iOS)
            .toolbar(removing: wide ? nil : .title)
            .toolbarVisibility(wide ? .automatic : .hidden, for: .tabBar)
                #endif
                .toolbar {
                    // A quiet action in the text's colour, as the design has it, not the accent.
                    ToolbarItem(placement: .primaryAction) { aside }
                }
        }
    }
}

/// A muscle an exercise works, as a chip: the main ones filled.
private struct MuscleChip: View {
    let label: String
    let primary: Bool

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(primary ? Ink.ground : Ink.text2)
            .padding(.horizontal, 11)
            .frame(minHeight: 28)
            .background(primary ? Ink.text : Ink.raised, in: .capsule)
    }
}

/// The estimated one-rep max over time: the line over a soft fill, the latest point marked.
struct EstimateLine: View {
    let points: [ExerciseDetailContent.Point]
    let domain: ClosedRange<Double>

    private static let fill = LinearGradient(
        colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.03)], startPoint: .top, endPoint: .bottom)

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Day", point.date), yStart: .value("Floor", domain.lowerBound), yEnd: .value("Estimate", point.value))
                    .foregroundStyle(Self.fill)
                LineMark(x: .value("Day", point.date), y: .value("Estimate", point.value))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            if let last = points.last {
                PointMark(x: .value("Day", last.date), y: .value("Estimate", last.value))
                    .symbolSize(70)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Ink.hairline)
            }
        }
        .frame(height: 96)
    }
}

/// What the exercise screen shows, worked out off `body`: the person's record with it and what's
/// said about it, and the substitutes in their gym.
struct ExerciseDetailContent {
    struct Point: Identifiable {
        var date: Date
        var value: Double
        var id: Date { date }
    }

    var record: ExerciseRecord
    var sentence: String?
    var score: Double?
    var bodyweightRatio: Double?
    /// The line in the gym's unit, and the range it's drawn over.
    var points: [Point]
    var domain: ClosedRange<Double>
    /// The dates under the line: the first, the middle and the last ("Today" when it's today).
    var scale: [String]
    var substitutes: [Exercise]

    @MainActor
    init(exercise: Exercise, model: AppModel) {
        let unit = model.gym.unit
        let record = model.record(for: exercise)
        self.record = record
        sentence = record.trendSentence(unit: unit)
        let strength = model.analysis?.strength
        score = strength.flatMap { record.score(for: exercise, bodyweightKg: $0.bodyweightKg, sex: $0.sex) }
        // Only where it means something: a free-weight lift the standards know, loaded as the
        // standards are (the bar, or the body plus what's added).
        if let strength, strength.bodyweightKg > 0, exercise.strength != nil, [.external, .bodyweightPlus].contains(exercise.loadBasis),
            let current = record.current
        {
            bodyweightRatio = current / strength.bodyweightKg
        }
        let points = record.trend.map { Point(date: $0.day.date(), value: unit.fromKilograms($0.e1rm)) }
        self.points = points
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.15, unit == .kg ? 1 : 2)
        domain = (low - pad)...(high + pad)
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        if let first = record.trend.first, let last = record.trend.last, first.day != last.day {
            let middle = first.day.adding(days: first.day.days(until: last.day) / 2)
            scale = [
                Format.day(first.day, style: style), Format.day(middle, style: style),
                last.day == model.today ? "Today" : Format.day(last.day, style: style),
            ]
        } else {
            scale = []
        }
        substitutes = Substitutions.candidates(
            for: exercise, in: model.catalog.all, availability: model.gym.availability, injuries: model.analysis?.life.injuries ?? [],
            avoid: model.settings.avoid, limit: 8)
    }

    /// Up in the good colour, down in the caution one, level and one session quiet.
    var movementColor: Color {
        guard let movement = record.movement, sentence?.hasPrefix("Level") == false else { return Ink.text2 }
        return movement.kg > 0 ? Ink.good : Ink.ok
    }
}
