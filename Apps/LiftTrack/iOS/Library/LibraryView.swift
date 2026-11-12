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

    /// Each filter set, as a chip that clears it.
    var chips: [(title: String, clear: (inout LibraryFilters) -> Void)] {
        var chips: [(String, (inout LibraryFilters) -> Void)] = []
        if let kind { chips.append((kind.label, { $0.kind = nil })) }
        if let pattern { chips.append((pattern.label, { $0.pattern = nil })) }
        if let equipment { chips.append((equipment.label, { $0.equipment = nil })) }
        if let muscle { chips.append((muscle.label, { $0.muscle = nil })) }
        if let easyOn { chips.append(("Easy on the \(easyOn.label.lowercased())", { $0.easyOn = nil })) }
        if inMyGym { chips.append(("In my gym", { $0.inMyGym = false })) }
        if safeWithInjuries { chips.append(("Safe with my injuries", { $0.safeWithInjuries = false })) }
        return chips
    }
}

/// Every exercise, searchable and filterable, beside the one chosen: what it is, what it costs,
/// what could replace it, and the person's own history with it.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filters = LibraryFilters()
    @State private var selection: Exercise.ID?
    @State private var results: [Exercise] = []

    /// What the list depends on: a change to any of it filters again.
    private struct Key: Hashable {
        var query: String
        var filters: LibraryFilters
        var gym: Gym
        var injuries: [Injury]
    }

    var body: some View {
        NavigationSplitView {
            list
                .navigationTitle("Library")
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
        } detail: {
            NavigationStack {
                if let selection, let exercise = model.catalog[selection] {
                    ExerciseDetailView(exercise: exercise) { self.selection = $0 }
                        .id(exercise.id)
                } else {
                    ContentUnavailableView(
                        "Choose an exercise", systemImage: "books.vertical",
                        description: Text("Its cue, muscles and joints, what could replace it, and your history with it.")
                    )
                    .navigationTitle("Library")
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
    }

    private var list: some View {
        let inProgram = model.currentMesocycle?.exerciseIDs ?? []
        return List(selection: $selection) {
            if !filters.isEmpty {
                Section {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(filters.chips.enumerated()), id: \.offset) { _, chip in
                            Button {
                                chip.clear(&filters)
                            } label: {
                                Label(chip.title, systemImage: "xmark.circle.fill").font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .accessibilityLabel("Remove filter: \(chip.title)")
                        }
                    }
                    .listRowSeparator(.hidden)
                } footer: {
                    Text("\(results.count) of \(model.catalog.all.count) exercises")
                }
            }
            ForEach(results) { exercise in
                LibraryRow(
                    exercise: exercise, inProgram: inProgram.contains(exercise.id), setAside: model.settings.avoid.contains(exercise.id),
                    ruledOut: model.analysis?.life.injuries.contains { $0.excludes(exercise) } ?? false
                )
                .tag(exercise.id)
                .contextMenu { rowMenu(exercise) }
                .accessibilityIdentifier("library.row")
            }
        }
        .searchable(text: $query, prompt: "Exercises, muscles, equipment")
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { filterMenu }
        }
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

    private var filterMenu: some View {
        Menu {
            Picker("Kind", selection: $filters.kind) {
                Text("Every kind").tag(ExerciseKind?.none)
                ForEach(ExerciseKind.allCases, id: \.self) { Text($0.label).tag(ExerciseKind?.some($0)) }
            }
            Picker("Movement", selection: $filters.pattern) {
                Text("Any movement").tag(MovementPattern?.none)
                ForEach(ExerciseFilter.patterns(in: model.catalog.all, kind: filters.kind)) { Text($0.label).tag(MovementPattern?.some($0)) }
            }
            .pickerStyle(.menu)
            Picker("Equipment", selection: $filters.equipment) {
                Text("Any equipment").tag(Equipment?.none)
                ForEach(ExerciseFilter.equipment(in: model.catalog.all, kind: filters.kind)) { Text($0.label).tag(Equipment?.some($0)) }
            }
            .pickerStyle(.menu)
            Picker("Muscle", selection: $filters.muscle) {
                Text("Any muscle").tag(Muscle?.none)
                ForEach(Muscle.allCases) { Text($0.label).tag(Muscle?.some($0)) }
            }
            .pickerStyle(.menu)
            Picker("Easy on", selection: $filters.easyOn) {
                Text("Any joint").tag(Joint?.none)
                ForEach(Joint.allCases) { Text($0.label).tag(Joint?.some($0)) }
            }
            .pickerStyle(.menu)
            Divider()
            Toggle("In My Gym", isOn: $filters.inMyGym)
            Toggle("Safe with My Injuries", isOn: $filters.safeWithInjuries)
            if !filters.isEmpty {
                Divider()
                Button("Clear Filters", role: .destructive) { filters = LibraryFilters() }
            }
        } label: {
            Label("Filter", systemImage: filters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .help("Filter by kind, movement, equipment, muscle, joint, your gym and your injuries")
        .accessibilityIdentifier("library.filter")
    }

    private func filter() {
        let filter = ExerciseFilter(
            kind: filters.kind, pattern: filters.pattern, equipment: filters.equipment, muscle: filters.muscle, easyOn: filters.easyOn,
            availability: filters.inMyGym ? model.gym.availability : nil,
            injuries: filters.safeWithInjuries ? model.analysis?.life.injuries ?? [] : nil)
        results = filter.apply(to: model.catalog.all, query: query)
    }
}

/// An exercise in the list: its name, what it is, and whether it's in the program, set aside, or
/// ruled out by an injury.
private struct LibraryRow: View {
    let exercise: Exercise
    let inProgram: Bool
    let setAside: Bool
    let ruledOut: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).lineLimit(1)
                Text(exercise.kindLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if inProgram {
                Image(systemName: "calendar").foregroundStyle(.tint).help("In this block").accessibilityLabel("In this block")
            }
            if ruledOut {
                Image(systemName: "bandage").foregroundStyle(Ink.ok).help("Ruled out by an injury").accessibilityLabel("Ruled out by an injury")
            }
            if setAside {
                Image(systemName: "nosign").foregroundStyle(.secondary).help("Set aside").accessibilityLabel("Set aside")
            }
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

/// One exercise in full.
struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let exercise: Exercise
    /// Shows another exercise in the library: a substitute picked here.
    let select: (String) -> Void
    @State private var record: ExerciseRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                status
                if sizeClass.isWide {
                    HStack(alignment: .top, spacing: 16) {
                        ExerciseFacts(exercise: exercise).card()
                        VStack(spacing: 16) {
                            history
                            substitutes
                        }
                    }
                } else {
                    ExerciseFacts(exercise: exercise).card()
                    history
                    substitutes
                }
            }
            .padding()
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.pageBackground)
        .navigationTitle(exercise.name)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { asideButton }
        }
        .task(id: model.sessions.count) { record = model.record(for: exercise) }
        .accessibilityIdentifier("library.detail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name).font(.largeTitle.bold())
            Text(exercise.kindLine).font(.headline).foregroundStyle(.secondary)
            if !exercise.aliases.isEmpty {
                Text("Also called \(exercise.aliases.joined(separator: ", "))").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var asideButton: some View {
        if model.settings.avoid.contains(exercise.id) {
            Button("Allow Back", systemImage: "arrow.uturn.backward") { model.setAside(exercise.id, false) }
                .labelStyle(.titleAndIcon)
                .help("Let the program use it again")
                .accessibilityIdentifier("library.allowBack")
        } else if exercise.kind == .strength {
            Button("Set Aside", systemImage: "nosign") { model.setAside(exercise.id, true) }
                .labelStyle(.titleAndIcon)
                .help("Never programme it; today's session swaps it out")
                .accessibilityIdentifier("library.setAside")
        }
    }

    /// Set aside, ruled out by an injury, or in this block, with what to do about it.
    @ViewBuilder
    private var status: some View {
        let days = model.currentMesocycle?.days.filter { $0.strengthSlots.contains { $0.exerciseID == exercise.id } } ?? []
        let injuries = model.activeInjuries.compactMap { period -> (LifeModePeriod, Injury)? in
            if case .injury(let injury) = period.kind, injury.affects(exercise) || injury.removed.contains(exercise.id) { return (period, injury) }
            return nil
        }
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
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("library.injuryOverride")
                    }
                }
            }
            .font(.subheadline)
            .card()
        }
    }

    @ViewBuilder
    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your history").font(.headline)
            if let record, !record.isEmpty {
                let unit = model.gym.unit
                HStack(spacing: 20) {
                    stat("\(record.sessions)", record.sessions == 1 ? "session" : "sessions")
                    if let last = record.lastDone { stat(Format.day(last, style: .dateTime.month(.abbreviated).day()), "last done") }
                    if let current = record.current { stat(Format.weight(current, unit: unit), "est. 1RM") }
                    if let change = record.change { stat("\(change >= 0 ? "+" : "")\(Format.percent(change))", "since the first") }
                }
                if record.trend.count >= 2 {
                    Chart(record.trend, id: \.day) { point in
                        LineMark(x: .value("Day", point.day.date()), y: .value("e1RM", unit.fromKilograms(point.e1rm)))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Day", point.day.date()), y: .value("e1RM", unit.fromKilograms(point.e1rm))).symbolSize(24)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxisLabel(unit.symbol)
                    .frame(height: 200)
                    .accessibilityLabel("\(exercise.name) estimated one-rep max over time")
                }
                if !record.bestSets.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Best sets").font(.subheadline.weight(.semibold))
                        ForEach(record.bestSets, id: \.set.id) { best in
                            HStack {
                                Text(Format.logged(best.set, exercise: exercise, unit: unit)).monospacedDigit()
                                RatingMark(rating: best.set.rating)
                                Spacer()
                                Text(Format.day(Day(best.set.date), style: .dateTime.month(.abbreviated).day().year())).foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            } else {
                Text("Not done yet. Once it's in a session, its sets and estimated one-rep max show here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var substitutes: some View {
        let options = Substitutions.candidates(
            for: exercise, in: model.catalog.all, availability: model.gym.availability, injuries: model.analysis?.life.injuries ?? [],
            avoid: model.settings.avoid, limit: 8)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Substitutes in your gym").font(.headline)
            if options.isEmpty {
                Text("Nothing else in your gym trains the same thing.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(options) { option in
                Button {
                    select(option.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name)
                            Text(option.kindLine).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .hoverHighlight()
                .accessibilityIdentifier("library.substitute")
            }
        }
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
