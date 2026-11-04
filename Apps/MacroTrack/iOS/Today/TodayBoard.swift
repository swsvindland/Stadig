import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// Today with room for it (iPad, the Mac, Vision Pro): what's left and what to do beside the day's
/// log as a table with every macro per entry, an entry edited in an inspector, the day stepped with
/// ⌘[ and ⌘] or picked from a calendar, and every way to log in the toolbar.
struct TodayBoard: View {
    @Environment(AppModel.self) private var model
    @State private var selection: FoodEntry.ID?
    @State private var editing = false
    @State private var sortOrder = [KeyPathComparator(\FoodEntry.date)]
    /// The moment being named as a saved meal.
    @State private var savingMeal: Moment?

    var body: some View {
        let entries = model.allEntries(on: model.selectedDay)
        NavigationStack {
            HStack(spacing: 0) {
                // Vision Pro's larger type needs more room for the weigh-in's words beside its field.
                summary.frame(
                    minWidth: Platform.isVision ? 390 : 320, idealWidth: Platform.isVision ? 410 : 360, maxWidth: Platform.isVision ? 440 : 400)
                Divider()
                log(entries)
                    .overlay {
                        if entries.isEmpty {
                            ContentUnavailableView {
                                Label(
                                    model.selectedDay == model.today ? "Nothing logged yet today" : "Nothing logged on this day",
                                    systemImage: "fork.knife")
                            } description: {
                                Text("Search, describe, drop in a photo or quick add. Foods eaten together are kept together.")
                            } actions: {
                                Button("Log Food") { model.openLogger(.search) }.primaryAction()
                            }
                            .accessibilityIdentifier("today.nothingLogged")
                        }
                    }
            }
            .navigationTitle("Today")
            .toolbar { LogToolbar() }
            .sideInspector(isPresented: $editing, min: 300, ideal: 340, max: 420) {
                if let entry = entries.first(where: { $0.id == selection }) {
                    EntryEditor(entry: entry, close: { editing = false }).id(entry.id)
                } else {
                    ContentUnavailableView("No entry selected", systemImage: "fork.knife", description: Text("Select a food to change it."))
                }
            }
        }
        .saveMealPrompt(
            isPresented: Binding(get: { savingMeal != nil }, set: { if !$0 { savingMeal = nil } }), entries: savingMeal?.entries ?? []
        )
        .onChange(of: selection) { _, selected in if selected != nil { editing = true } }
        .onChange(of: editing) { _, open in if !open { selection = nil } }
        .onChange(of: model.selectedDay) { _, _ in selection = nil }
    }

    /// The ring, the weight, the day's actions and quick logs: the phone's Today, in its order,
    /// without its log.
    var summary: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    SummaryCard(day: model.selectedDay)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                WeightSection(day: model.selectedDay)
                TodayFood(day: model.selectedDay)
                DayStateSection(day: model.selectedDay)
                TodayMore(day: model.selectedDay)
            }
            .insetGroupedList()
            .sectionSpacing(14)
            .refreshable { await model.refreshHealth() }
            .onChange(of: model.supplementsScrollRequest) { _, _ in
                withAnimation { proxy.scrollTo(SupplementsSection.scrollID, anchor: .top) }
            }
        }
    }

    /// Sorted by time, the log keeps its moments (foods eaten together, with their time and total);
    /// sorted by anything else, it's one list.
    func log(_ entries: [FoodEntry]) -> some View {
        let byTime = sortOrder.first.map { $0.keyPath == \FoodEntry.date && $0.order == .forward } ?? true
        let moments = byTime ? Timeline.moments(entries) : []
        let gaps = byTime ? model.gapsBefore(on: model.selectedDay) : [:]
        let sorted = byTime ? [] : entries.sorted(using: sortOrder)
        return Table(of: FoodEntry.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Time", value: \.date) { entry in
                HStack(spacing: 4) {
                    if model.foodLog.isUpcoming(entry) { LaterMark() }
                    Text(Format.time(entry.date)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            // Room for "12:30 PM", and for the header's sort arrow: the log starts out sorted by time.
            .width(min: 84, ideal: 92)
            TableColumn("Food", value: \.name) { entry in
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name).lineLimit(1)
                    if let brand = entry.brand { Text(brand).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                .opacity(model.foodLog.isUpcoming(entry) ? 0.55 : 1)
                .help(entry.name)
            }
            .width(min: 140)
            TableColumn("Amount") { entry in Text(entry.amountLabel).foregroundStyle(.secondary).lineLimit(1).help(entry.amountLabel) }
                .width(min: 60, ideal: 80)
            TableColumn("kcal", value: \.nutrients.kcal) { entry in
                Text("\(entry.isEstimate ? "≈" : "")\(Format.whole(entry.nutrients.kcal))").monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .opacity(model.foodLog.isUpcoming(entry) ? 0.55 : 1)
            }
            .width(min: 44, ideal: 50)
            TableColumn("Protein", value: \.nutrients.protein) { entry in
                NumberCell(entry.nutrients.protein, unit: "g")
            }
            // Room for its header, the longest of the numbers'.
            .width(min: 64, ideal: 72)
            TableColumn("Carbs", value: \.nutrients.carbs) { entry in NumberCell(entry.nutrients.carbs, unit: "g") }
                .width(min: 44, ideal: 50)
            TableColumn("Fat", value: \.nutrients.fat) { entry in NumberCell(entry.nutrients.fat, unit: "g") }
                .width(min: 40, ideal: 46)
            TableColumn("Fiber") { entry in NumberCell(entry.nutrients.fiber, unit: "g") }
                .width(min: 40, ideal: 46)
        } rows: {
            if byTime {
                ForEach(moments) { moment in
                    Section {
                        ForEach(moment.entries) { entry in row(entry, moment: moment) }
                    } header: {
                        HStack {
                            Text(Format.time(moment.start)).fontWeight(.semibold)
                            if let gap = gaps[moment.id] { GapBadge(gap: gap) }
                            Spacer()
                            Text("\(Format.kcal(moment.nutrients.kcal)) · \(Format.macros(moment.nutrients))").monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ForEach(sorted) { entry in row(entry, moment: nil) }
            }
        }
        #if os(macOS)
        .onDeleteCommand {
            if let selection { model.delete(entries: [selection]) }
        }
        #endif
        .accessibilityIdentifier("today.log")
    }

    func row(_ entry: FoodEntry, moment: Moment?) -> some TableRowContent<FoodEntry> {
        TableRow(entry)
            .contextMenu {
                Button("Edit", systemImage: "pencil") {
                    selection = entry.id
                    editing = true
                }
                Button("Log Again Now", systemImage: "arrow.clockwise") {
                    model.log([LogAgain.copy(entry, to: model.logDate(), source: .copied)])
                }
                if let moment {
                    Button("Add to \(Format.time(moment.start))…", systemImage: "plus") {
                        model.openLogger(.search, at: moment.end.addingTimeInterval(60))
                    }
                    if moment.entries.count > 1 {
                        Button("Log All \(moment.entries.count) Again", systemImage: "arrow.clockwise") { model.logAgain(moment) }
                    }
                    MomentMealButton(moment: moment, titleCase: true) { savingMeal = moment }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entries: [entry.id]) }
                if let moment, moment.entries.count > 1 {
                    Button("Delete All \(moment.entries.count)", systemImage: "trash", role: .destructive) {
                        model.delete(entries: moment.entries.map(\.id))
                    }
                }
            }
    }
}

/// Every way to log, in the toolbar where there's no bar of them above the tabs.
struct LogToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.openLogger(.search)
            } label: {
                Label("Log Food", systemImage: "magnifyingglass")
            }
            .help("Find a food to log (⌘L)")
            .accessibilityIdentifier("toolbar.logFood")
            Button {
                model.openLogger(.describe)
            } label: {
                Label("Describe a Meal", systemImage: "text.bubble")
            }
            .help("Describe a meal in words")
            .accessibilityIdentifier("toolbar.describe")
            Button {
                model.openLogger(Camera.isAvailable ? .camera : .photoLibrary)
            } label: {
                Label("Log a Photo", systemImage: Camera.isAvailable ? "camera" : "photo.on.rectangle")
            }
            .help(Camera.isAvailable ? "Take a photo of a meal" : "Choose a photo of a meal, or drop one on the window")
            .accessibilityIdentifier("toolbar.photo")
            Button {
                model.openLogger(.quickAdd)
            } label: {
                Label("Quick Add", systemImage: "plus.forwardslash.minus")
            }
            .help("Add calories and protein")
            .accessibilityIdentifier("toolbar.quickAdd")
            Button {
                model.showWeighIn = true
            } label: {
                Label("Weigh In", systemImage: "scalemass")
            }
            .help("Record a weigh-in")
            .accessibilityIdentifier("toolbar.weighIn")
            SettingsButton(identifier: "today.settings")
        }
    }
}
