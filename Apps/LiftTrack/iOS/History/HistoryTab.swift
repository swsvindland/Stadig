import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// Every session and outside activity. On the iPad and the Mac, a sortable table with the session's
/// sets beside it; in a narrow window, the phone's list.
struct HistoryTab: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass.isWide {
                    HistoryTable()
                } else {
                    HistoryView()
                }
            }
            .sessionResumeToolbar()
        }
    }
}

/// Sessions and activities in a table: sort by any column, search by name or exercise, select one
/// to see its sets, delete from the context menu or with the Delete key.
struct HistoryTable: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\HistoryRow.date, order: .reverse)]
    @State private var selection: Set<HistoryRow.ID> = []
    @State private var query = ""
    @State private var rows: [HistoryRow] = []
    @State private var inspecting = true
    /// The table's width, for which columns fit (`allColumns`); 0 until it's laid out.
    @State private var tableWidth: CGFloat = 0
    /// Rows waiting on "Delete?": a key press or several at once is easy to make by accident.
    @State private var confirming: [HistoryRow] = []
    /// The search field has the keyboard: ⌘F gives it it.
    @FocusState private var searching: Bool

    private struct Key: Equatable {
        var rows: [HistoryRow]
        var sortOrder: [KeyPathComparator<HistoryRow>]
        var query: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                PageHeader(eyebrow: "\(model.sessions.count) sessions · \(model.activities.count) activities", title: "History")
                InkSearchField(text: $query, prompt: "Sessions, exercises, activities", identifier: "history.search")
                    .focused($searching)
                    .frame(maxWidth: 420)
            }
            .padding(.horizontal, 16)
            table
        }
        .background(.pageBackground)
        .navigationTitle("History")
        .ownHeader()
        .toolbar {
            #if !os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button("Delete", systemImage: "trash", role: .destructive) { delete(selection, confirm: true) }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(selection.isEmpty)
                    .accessibilityIdentifier("history.deleteSelected")
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspecting.toggle()
                } label: {
                    Label(inspecting ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help(inspecting ? "Hide the inspector" : "Show the inspector")
            }
        }
        .sideInspector(isPresented: $inspecting) {
            HistoryInspector(row: selection.count == 1 ? rows.first { selection.contains($0.id) } : nil, count: selection.count)
        }
        .confirmationDialog(
            confirming.count == 1 ? "Delete this \(confirming[0].isSession ? "session" : "activity")?" : "Delete \(confirming.count) items?",
            isPresented: Binding(get: { !confirming.isEmpty }, set: { if !$0 { confirming = [] } }), titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                model.delete(historyRows: confirming)
                selection.subtract(confirming.map(\.id))
                confirming = []
            }
            .accessibilityIdentifier("history.confirmDelete")
        } message: {
            Text("Sessions leave Apple Health too. This can't be undone.")
        }
        .onChange(of: model.searchRequested, initial: true) { _, requested in
            guard requested, model.tab == .history else { return }
            searching = true
            model.searchRequested = false
        }
        .task(id: Key(rows: model.historyRows, sortOrder: sortOrder, query: query)) {
            rows = model.historyRows.filter { query.isEmpty || $0.matches(query) }.sorted(using: sortOrder)
        }
        .accessibilityIdentifier("history.table")
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date) { row in
                Text(row.date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .monospacedDigit()
            }
            .width(min: width(150, 200), ideal: 190)
            TableColumn("Name", value: \.name) { row in
                Label(row.name, systemImage: symbol(row)).labelStyle(.titleAndIcon)
            }
            .width(min: width(140, 130), ideal: 220)
            TableColumn("Minutes", value: \.minutes) { row in Text("\(row.minutes)").monospacedDigit() }
                .width(min: 54, ideal: 70, max: cap(80))
            if allColumns {
                TableColumn("Work sets", value: \.workSets) { row in
                    Text(row.isSession ? "\(row.workSets)" : "—").monospacedDigit()
                }
                .width(min: 64, ideal: 80, max: cap(96))
            }
            TableColumn("Top set or effort", value: \.topSetE1RM) { row in
                Text(topSet(row)).lineLimit(1).help(topSet(row))
            }
            .width(min: 140, ideal: 240)
            if allColumns {
                TableColumn("Recorded on", value: \.source).width(min: 110, ideal: 130)
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            tableWidth = $0
        }
        .contextMenu(forSelectionType: HistoryRow.ID.self) { ids in
            if !ids.isEmpty {
                Button(ids.count == 1 ? "Delete" : "Delete \(ids.count) Items", systemImage: "trash", role: .destructive) {
                    delete(ids, confirm: ids.count > 1)
                }
                .accessibilityIdentifier("history.delete")
            }
        } primaryAction: { _ in
            inspecting = true
        }
        #if os(macOS)
        .onDeleteCommand { delete(selection, confirm: true) }
        #endif
        .inkList()
        .overlay {
            if rows.isEmpty {
                Text(query.isEmpty ? "Sessions and outside activities show here." : "Nothing called \u{201C}\(query)\u{201D}.")
                    .font(.subheadline).foregroundStyle(Ink.text2).padding(24)
            }
        }
    }

    /// A column's least width: the Mac's, for its 13-point table text, or iPad's and Vision Pro's,
    /// for text at 17.
    private func width(_ mac: CGFloat, _ touch: CGFloat) -> CGFloat { Platform.isMac ? mac : touch }

    /// The most a number's column takes on iPad and Vision Pro, whose tables share the room out
    /// evenly rather than by ideal width: what's left goes to the date, the name and the top set.
    private func cap(_ touch: CGFloat) -> CGFloat? { Platform.isMac ? nil : touch }

    /// Room for every column. An iPad in portrait with the inspector beside the table has room for
    /// four readable ones, not six that run off the screen: work sets (the inspector lists a
    /// selected session's sets) and where it was recorded give way.
    private var allColumns: Bool { Platform.isMac || tableWidth == 0 || tableWidth >= 880 }

    /// A single row from the context menu goes at once, as a swipe does on the phone; the Delete key
    /// and several rows at once ask first.
    private func delete(_ ids: Set<HistoryRow.ID>, confirm: Bool) {
        let doomed = rows.filter { ids.contains($0.id) }
        guard !doomed.isEmpty else { return }
        if confirm {
            confirming = doomed
        } else {
            model.delete(historyRows: doomed)
            selection.subtract(ids)
        }
    }

    private func symbol(_ row: HistoryRow) -> String {
        switch row.kind {
        case .session: "figure.strengthtraining.traditional"
        case .activity(let type): type.symbol
        }
    }

    private func topSet(_ row: HistoryRow) -> String {
        guard let top = row.topSet else { return row.effort.map { "Effort \($0) of 10" } ?? "—" }
        let exercise = model.catalog.resolve(top.set.exerciseID)
        return "\(exercise.name) · \(Format.logged(top.set, exercise: exercise, unit: model.gym.unit))"
    }
}

/// The selected row in full: a session's sets, or an activity's details.
private struct HistoryInspector: View {
    @Environment(AppModel.self) private var model
    let row: HistoryRow?
    let count: Int

    var body: some View {
        if let row {
            if row.isSession, let session = model.sessions.first(where: { $0.id == row.id }) {
                SessionSetsList(record: session, header: true)
            } else if let activity = model.activities.first(where: { $0.id == row.id }) {
                ActivityDetail(log: activity)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(count > 1 ? "\(count) selected" : "Nothing selected").font(.headline).foregroundStyle(Ink.text)
                if count <= 1 { Text("Select a session to see its sets.").font(.subheadline).foregroundStyle(Ink.text2) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// An outside activity's details.
struct ActivityDetail: View {
    let log: ActivityLog

    var body: some View {
        Form {
            Section {
                Label(log.type.label, systemImage: log.type.symbol).font(.title3.bold())
                LabeledContent("When", value: log.start.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Minutes", value: "\(log.minutes)")
                LabeledContent("Effort", value: "\(log.intensity) of 10")
                if let hr = log.averageHeartRate { LabeledContent("Average heart rate", value: "\(Int(hr)) bpm") }
                if let distance = log.distanceMeters { LabeledContent("Distance", value: "\(Format.number(distance / 1000, digits: 2)) km") }
                LabeledContent("From", value: source)
            }
            if let martial = log.martialArts {
                Section {
                    LabeledContent("Type", value: martial.classType.label)
                    LabeledContent("Sparring rounds", value: "\(martial.sparringRounds)")
                    if let gassed = martial.roundsBeforeGassed { LabeledContent("Gassed after", value: "Round \(gassed)") }
                } header: {
                    Text("Class").eyebrow()
                }
            }
            if !log.note.isEmpty {
                Section {
                    Text(log.note)
                } header: {
                    Text("Note").eyebrow()
                }
            }
        }
        .inkList()
        .formStyle(.grouped)
    }

    private var source: String {
        switch log.source {
        case .health(_, let name): "Apple Health (\(name))"
        case .manual: "Logged by hand"
        case .declared: "Your regular \(log.type.label.lowercased())"
        }
    }
}
