import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// Every day logged, as a table where there's room for one: calories against that day's own
/// target, the macros, how complete the log is, the weigh-in and the trend, sorted by any column.
/// The selected day's log is beside it. The rows come from the analysis, worked out off the main
/// thread whenever it changes.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [HistoryDay] = []
    @State private var shown: [HistoryDay] = []
    @State private var loaded = false
    @State private var selection: Day?
    @State private var sortOrder = [HistoryOrder(.day, order: .reverse)]
    @State private var inspecting = true
    /// The table's width, for which columns fit (`allColumns`); 0 until it's laid out.
    @State private var tableWidth: CGFloat = 0

    var body: some View {
        NavigationStack {
            table
                .overlay {
                    if !loaded {
                        ProgressView()
                    } else if rows.isEmpty {
                        ContentUnavailableView(
                            "No history yet", systemImage: "calendar", description: Text("Each day you log or weigh in appears here."))
                    }
                }
                .navigationTitle("History")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            inspecting.toggle()
                        } label: {
                            Label(inspecting ? "Hide Day" : "Show Day", systemImage: "sidebar.trailing")
                        }
                        .help(inspecting ? "Hide the day's log" : "Show the day's log")
                    }
                }
                .sideInspector(isPresented: $inspecting, min: 280, ideal: 320, max: 440) {
                    if let selection {
                        HistoryDayDetail(day: selection, row: rows.first { $0.day == selection })
                    } else {
                        ContentUnavailableView("No day selected", systemImage: "calendar", description: Text("Select a day to see its log."))
                    }
                }
        }
        .task(id: model.analysisVersion) { await load() }
        .onChange(of: sortOrder) { _, order in shown = rows.sorted(using: order) }
    }

    var table: some View {
        let unit = model.units.weight
        return Table(shown, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", sortUsing: HistoryOrder(.day, order: .reverse)) { row in
                Text(Format.historyDay(row.day, today: model.today)).monospacedDigit().lineLimit(1)
            }
            .width(min: width(84, 100), ideal: 96)
            // "1,800 / 2,400" where there's room; the target alone gives way in a narrow table, as
            // vs Target says how far over or under.
            TableColumn("Calories", sortUsing: HistoryOrder(.kcal, order: .reverse)) { row in KcalCell(row: row, target: allColumns) }
                .width(min: 72, ideal: 92, max: cap(allColumns ? 120 : 72))
            TableColumn("vs Target", sortUsing: HistoryOrder(.overTarget, order: .reverse)) { row in OverTargetCell(row: row) }
                .width(min: 48, ideal: 56, max: cap(76))
            TableColumn("Protein", sortUsing: HistoryOrder(.protein, order: .reverse)) { row in NumberCell(row.intake?.protein, unit: "g") }
                .width(min: 44, ideal: 50, max: cap(64))
            if allColumns {
                TableColumn("Carbs", sortUsing: HistoryOrder(.carbs, order: .reverse)) { row in NumberCell(row.intake?.carbs, unit: "g") }
                    .width(min: 44, ideal: 48, max: cap(64))
                TableColumn("Fat", sortUsing: HistoryOrder(.fat, order: .reverse)) { row in NumberCell(row.intake?.fat, unit: "g") }
                    .width(min: 40, ideal: 46, max: cap(64))
                TableColumn("Fiber", sortUsing: HistoryOrder(.fiber, order: .reverse)) { row in NumberCell(row.intake?.fiber, unit: "g") }
                    .width(min: 40, ideal: 46, max: cap(64))
            }
            TableColumn("Status", sortUsing: HistoryOrder(.status)) { row in StatusCell(row: row) }
                .width(min: width(84, 108), ideal: 100)
            if allColumns && model.tracksMealTiming {
                TableColumn("Overnight", sortUsing: HistoryOrder(.overnightFast, order: .reverse)) { row in
                    Text(row.overnightFast.map(Format.duration) ?? "—").monospacedDigit()
                        .foregroundStyle(row.overnightFast == nil ? .tertiary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help("From the last meal the evening before to the day's first")
                }
                .width(min: 60, ideal: 72, max: cap(84))
            }
            TableColumn("Weigh-in", sortUsing: HistoryOrder(.weighIn, order: .reverse)) { row in
                Text(row.weighIn.map { Format.weight($0, unit: unit) } ?? "—").monospacedDigit()
                    .foregroundStyle(row.weighIn == nil ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 66, max: cap(72))
            TableColumn("Trend", sortUsing: HistoryOrder(.trend, order: .reverse)) { row in
                Text(row.trend.map { Format.weight($0, unit: unit) } ?? "—").monospacedDigit()
                    .foregroundStyle(row.trend == nil ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 66, max: cap(72))
        }
        #if os(macOS)
        // A double-click shows the day in Today.
        .contextMenu(forSelectionType: Day.self) { days in
            dayMenu(days)
        } primaryAction: { days in
            if let day = days.first { show(day) }
        }
        #else
        // A tap selects; the day's log beside it has Show in Log.
        .contextMenu(forSelectionType: Day.self) { days in dayMenu(days) }
        #endif
        .accessibilityIdentifier("history.table")
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            tableWidth = $0
        }
    }

    /// A column's least width: the Mac's, for its 13-point table text, or iPad's and Vision Pro's,
    /// for text at 17.
    func width(_ mac: CGFloat, _ touch: CGFloat) -> CGFloat { Platform.isMac ? mac : touch }

    /// The most a number's column takes on iPad and Vision Pro, whose tables share the room out
    /// evenly rather than by ideal width: what's left goes to the date and the status.
    func cap(_ touch: CGFloat) -> CGFloat? { Platform.isMac ? nil : touch }

    /// Room for every column. An iPad in portrait with the day beside the table has room for seven
    /// readable ones, not ten clipped ones: carbs, fat and fiber give way, as the day's log beside
    /// it has them.
    var allColumns: Bool { Platform.isMac || tableWidth == 0 || tableWidth >= 940 }

    @ViewBuilder
    func dayMenu(_ days: Set<Day>) -> some View {
        if let day = days.first {
            Button("Show in Log", systemImage: "list.bullet.clipboard") { show(day) }
            if day < model.today {
                Menu("Mark As") {
                    ForEach([DayState.complete, .partial, .fasting], id: \.self) { state in
                        Button(state.label) { model.setState(model.state(of: day) == state ? nil : state, for: day) }
                    }
                }
            }
        }
    }

    func show(_ day: Day) {
        model.selectedDay = day
        model.tab = .today
    }

    func load() async {
        guard let state = model.state, let analysis = model.analysis else {
            rows = []
            shown = []
            loaded = true
            return
        }
        let computed = await Task.detached(priority: .userInitiated) { DayHistory.rows(state, analysis) }.value
        guard !Task.isCancelled else { return }
        rows = computed
        shown = computed.sorted(using: sortOrder)
        loaded = true
        if selection == nil || !computed.contains(where: { $0.day == selection }) {
            // Yesterday is the last whole day; today, before there's one.
            selection = computed.dropFirst().first?.day ?? computed.first?.day
        }
    }
}

/// "2,140 / 2,300": the day's calories against its target, or the calories alone.
private struct KcalCell: View {
    let row: HistoryDay
    /// Whether the day's target follows the calories.
    let target: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(row.kcal.map(Format.whole) ?? "—").foregroundStyle(row.kcal == nil ? .tertiary : .primary)
            if target, let target = row.targets.kcal {
                Text("/ \(Format.whole(target))").foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
}

/// How far over or under the target a day ran, coloured only when it counts (a complete day).
private struct OverTargetCell: View {
    let row: HistoryDay

    var body: some View {
        if let over = row.kcalOverTarget {
            Text("\(over > 0 ? "+" : over < 0 ? "−" : "")\(Format.whole(abs(over)))")
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Text("—").foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    var color: Color {
        switch row.hit {
        case true?: .green
        case false?: .orange
        case nil: .secondary
        }
    }
}

/// Complete, fasted, partial, unknown or today, and any life mode the day was in.
struct StatusCell: View {
    let row: HistoryDay

    var body: some View {
        HStack(spacing: 4) {
            Label(row.status.label, systemImage: row.status.symbol)
                .foregroundStyle(row.status.color)
                .labelStyle(.titleAndIcon)
            if let mode = row.targets.mode.away { Text("· \(mode)").foregroundStyle(.secondary) }
        }
        .lineLimit(1)
    }
}

extension HistoryStatus {
    var symbol: String {
        switch self {
        case .complete: "checkmark.circle.fill"
        case .fasting: "moon.circle"
        case .partial: "circle.lefthalf.filled"
        case .unknown: "questionmark.circle"
        case .inProgress: "clock"
        }
    }

    var color: Color {
        switch self {
        case .complete: .green
        case .fasting: .teal
        case .partial: .orange
        case .unknown, .inProgress: .secondary
        }
    }
}

extension DailyTargets.Mode {
    /// The life mode a day was in, when it was one that changes what's expected.
    var away: String? {
        switch self {
        case .vacation: "Vacation"
        case .illness: "Ill"
        case .crunch: "Crunch"
        case .dietBreak: "Diet break"
        case .assessment, .phase: nil
        }
    }
}

/// A day's log: its numbers against its targets, how complete it is, and what was eaten when.
struct HistoryDayDetail: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let row: HistoryDay?

    var body: some View {
        let moments = Timeline.moments(model.allEntries(on: day))
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Format.day(day, style: .dateTime.weekday(.wide).month(.wide).day().year())).font(.headline)
                    if let row {
                        StatusCell(row: row).font(.subheadline)
                        NutrientSummary(nutrients: row.intake ?? .zero)
                        if let kcal = row.targets.kcal {
                            Text("Target \(Format.kcal(kcal))\(row.targets.protein.map { ", \(Format.grams($0)) protein" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if let protein = row.targets.protein {
                            Text("Target \(Format.grams(protein)) protein").font(.caption).foregroundStyle(.secondary)
                        }
                        if let kg = row.weighIn {
                            Label("Weighed \(Format.weight(kg, unit: model.units.weight))", systemImage: "scalemass").font(.caption)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if moments.isEmpty {
                Section { Text("Nothing logged on this day.").foregroundStyle(.secondary) }
            }
            ForEach(moments) { moment in
                Section {
                    ForEach(moment.entries) { entry in
                        EntryRow(entry: entry)
                            .contextMenu {
                                Button("Log Again Now", systemImage: "arrow.clockwise") {
                                    model.log([LogAgain.copy(entry, to: Date(), source: .copied)])
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entries: [entry.id]) }
                            }
                    }
                } header: {
                    HStack {
                        Text(Format.time(moment.start))
                        Spacer()
                        Text(Format.kcal(moment.nutrients.kcal)).monospacedDigit()
                    }
                }
            }
            DayStateSection(day: day)
            Section {
                Button("Show in Log", systemImage: "list.bullet.clipboard") { model.show(day: day) }
                    .accessibilityIdentifier("history.showInLog")
            }
        }
        .accessibilityIdentifier("history.day")
    }
}
