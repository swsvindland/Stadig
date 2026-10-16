import SwiftUI
import NutritionEngine
import SystemCore

/// What's left today, the one or two things worth doing, and the day's log. Built so a visit can
/// be a glance and a tap.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: FoodEntry?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryCard(day: model.selectedDay)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if model.selectedDay == model.today {
                    ActionsSection()
                    if !model.entries.isEmpty && !model.logAgain.isEmpty { LogAgainSection() }
                } else {
                    Section {
                        Label("Catching up \(Format.relative(model.selectedDay, today: model.today)). New entries land on that day.",
                              systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                    }
                }
                ForEach(MealSlot.allCases) { slot in
                    MealSection(slot: slot, editing: $editing)
                }
                DayStateSection(day: model.selectedDay)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(14)
            .navigationTitle(model.selectedDay == model.today ? "Today" : Format.day(model.selectedDay, style: .dateTime.weekday(.wide).month().day()))
            .toolbar { toolbar }
            .sheet(item: $editing) { entry in
                EntryEditor(entry: entry)
            }
            .refreshable { await model.refreshHealth() }
        }
    }

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                model.selectedDay = model.selectedDay.adding(days: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")
            if model.selectedDay < model.today {
                Button {
                    model.selectedDay = model.selectedDay.adding(days: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next day")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.selectedDay != model.today {
                Button("Today") { model.selectedDay = model.today }
            }
            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
    }
}

/// Calories left as a ring, with protein (and carbs and fat, if shown) as bars.
struct SummaryCard: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        if let analysis = model.analysis {
            let targets = analysis.targets
            let eaten = analysis.intakeByDay[day] ?? .zero
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    ZStack {
                        ProgressRing(value: eaten.kcal, target: targets.kcal, lineWidth: 13)
                        VStack(spacing: 0) {
                            if let kcal = targets.kcal {
                                let left = kcal - eaten.kcal
                                Text(Format.whole(abs(left))).font(.title.weight(.bold).monospacedDigit()).contentTransition(.numericText())
                                Text(left >= 0 ? "kcal left" : "kcal over").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(Format.whole(eaten.kcal)).font(.title.weight(.bold).monospacedDigit()).contentTransition(.numericText())
                                Text("kcal eaten").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .minimumScaleFactor(0.7)
                    }
                    .frame(width: 124, height: 124)
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .leading, spacing: 11) {
                        MacroBar(macro: .protein, eaten: eaten.protein, target: targets.protein)
                        if model.settings.showAllMacros {
                            MacroBar(macro: .carbs, eaten: eaten.carbs, target: targets.carbs)
                            MacroBar(macro: .fat, eaten: eaten.fat, target: targets.fat)
                        }
                        if let kcal = targets.kcal {
                            Text("\(Format.whole(eaten.kcal)) of \(Format.kcal(kcal))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ModeLine(targets: targets, assessment: analysis.assessment)
            }
            .card(padding: 18)
        }
    }
}

/// What today asks for, in a line: the mode and its note.
struct ModeLine: View {
    let targets: DailyTargets
    let assessment: AssessmentProgress?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let pill { Pill(text: pill.0, symbol: pill.1, color: pill.2) }
            Text(targets.note).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    var pill: (String, String, Color)? {
        switch targets.mode {
        case .assessment:
            assessment.map { ("Day \($0.day) of \($0.totalDays)", "magnifyingglass", .accentColor) } ?? ("Assessment", "magnifyingglass", .accentColor)
        case .dietBreak: ("Diet break", "pause.circle", .teal)
        case .crunch: ("Crunch", "briefcase.fill", .orange)
        case .illness: ("Ill", "thermometer.medium", .purple)
        case .vacation: ("Vacation", "airplane", .blue)
        case .phase: nil
        }
    }
}

/// The prescriptive cards: what was seen, and the one thing to do. Weighing in is inline.
struct ActionsSection: View {
    @Environment(AppModel.self) private var model
    @State private var weight = ""
    @FocusState private var weightFocused: Bool

    var body: some View {
        if let analysis = model.analysis {
            let actions = analysis.actions.filter { $0.kind != .weighIn }.prefix(2)
            let weighIn = analysis.actions.first { $0.kind == .weighIn }
            let checkIn = recentCheckIn
            if weighIn != nil || !actions.isEmpty || checkIn != nil {
                Section {
                    if weighIn != nil { weighInRow }
                    if let checkIn { CheckInRow(checkIn: checkIn, previous: model.checkIns.last { $0.day < checkIn.day }) }
                    ForEach(Array(actions)) { action in
                        ActionRow(action: action)
                    }
                }
            }
        }
    }

    /// A weigh-in in one field and one tap.
    var weighInRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "scalemass").foregroundStyle(Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Weigh in").font(.subheadline.weight(.semibold))
                Text("First thing, after the bathroom").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TextField(placeholder, text: $weight)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(width: 70)
                .focused($weightFocused)
            Text(model.units.weight.symbol).foregroundStyle(.secondary)
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(parsed == nil)
        }
    }

    var placeholder: String {
        model.latestWeighIn.map { Format.number(model.units.weight.fromKilograms($0.kg)) } ?? "0.0"
    }

    var parsed: Double? {
        guard let value = Double(weight.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return model.units.weight.toKilograms(value)
    }

    func save() {
        guard let kg = parsed else { return }
        weightFocused = false
        weight = ""
        model.weighIn(kg: kg)
    }

    /// This week's check-in, for a couple of days after it moved the targets.
    var recentCheckIn: CheckIn? {
        guard let last = model.checkIns.last, last.day.days(until: model.today) <= 2, model.checkIns.count > 1 else { return nil }
        return last
    }
}

struct CheckInRow: View {
    let checkIn: CheckIn
    let previous: CheckIn?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(checkIn.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    var title: String {
        guard let previous else { return "Targets set: \(Format.kcal(checkIn.kcal))" }
        let change = checkIn.kcal - previous.kcal
        if abs(change) < 5 { return "Weekly check-in: targets hold at \(Format.kcal(checkIn.kcal))" }
        return "Weekly check-in: \(Format.kcal(checkIn.kcal)) (\(change > 0 ? "+" : "−")\(Format.whole(abs(change))))"
    }
}

struct ActionRow: View {
    @Environment(AppModel.self) private var model
    let action: MacroAction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title).font(.subheadline.weight(.semibold))
                Text(action.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(action.action).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let button {
                Button(button.0, action: button.1).buttonStyle(.bordered).buttonBorderShape(.capsule).font(.subheadline)
            }
        }
    }

    var symbol: String {
        switch action.kind {
        case .weighIn, .weighInSoon: "scalemass"
        case .protein: "fish"
        case .logYesterday: "calendar.badge.exclamationmark"
        case .planReady: "sparkles"
        case .whoosh: "drop"
        case .reviewPlan: "checklist"
        }
    }

    var button: (String, () -> Void)? {
        switch action.kind {
        case .planReady, .reviewPlan: ("See plan", { model.tab = .plan })
        case .logYesterday: ("Catch up", { model.selectedDay = model.today.adding(days: -1) })
        case .protein: ("Log", { model.logger = .search })
        default: nil
        }
    }
}

/// Foods worth logging again right now, one tap each.
struct LogAgainSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.logAgain.prefix(10)) { item in
                        Button {
                            model.logAgain(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.template.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text("\(item.template.amountLabel) · \(Format.whole(item.template.nutrients.kcal))")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: 170, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.insetBackground, in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            ForEach(MealSlot.allCases) { slot in
                                Button("Log to \(slot.label)", systemImage: slot.symbol) { model.logAgain(item, meal: slot) }
                            }
                        }
                        .accessibilityLabel("Log \(item.template.name), \(item.template.amountLabel), \(Format.kcal(item.template.nutrients.kcal))")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } header: {
            Text("Log again")
        }
    }
}

/// One meal: its entries, its total, and quick ways to fill it.
struct MealSection: View {
    @Environment(AppModel.self) private var model
    let slot: MealSlot
    @Binding var editing: FoodEntry?

    var body: some View {
        let entries = model.entries(on: model.selectedDay).filter { $0.meal == slot }
        let usual = entries.isEmpty ? LogAgain.usual(slot, entries: model.entries, before: model.selectedDay) : nil
        Section {
            ForEach(entries) { entry in
                Button {
                    editing = entry
                } label: {
                    EntryRow(entry: entry)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entries: [entry.id]) }
                }
                .swipeActions(edge: .leading) {
                    Button("Again", systemImage: "arrow.clockwise") {
                        model.log([LogAgain.copy(entry, to: model.logSlot(slot).date, meal: slot, source: .copied)])
                    }
                    .tint(.accentColor)
                }
            }
            if let usual {
                Button {
                    model.copyUsual(slot)
                } label: {
                    Label("Same as \(Format.relative(usual.day, today: model.selectedDay)): \(usual.entries.map(\.name).prefix(3).joined(separator: ", "))",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
        } header: {
            HStack {
                Label(slot.label, systemImage: slot.symbol)
                Spacer()
                if !entries.isEmpty {
                    Text(Format.kcal(entries.map(\.nutrients.kcal).reduce(0, +))).monospacedDigit()
                }
                Button {
                    model.loggerMeal = slot
                    model.logger = .search
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityLabel("Add to \(slot.label)")
            }
        }
    }
}

struct EntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.body).lineLimit(1)
                Text([entry.brand, entry.amountLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.isEstimate ? "≈" : "")\(Format.whole(entry.nutrients.kcal))").font(.body.monospacedDigit())
                Text("\(Format.grams(entry.nutrients.protein)) P").font(.caption.monospacedDigit()).foregroundStyle(Macro.protein.color)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Whether the day's log is finished: complete days teach the estimate; partial days don't.
struct DayStateSection: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        let state = model.state(of: day)
        let hasEntries = !model.entries(on: day).isEmpty
        if hasEntries || state != nil || day < model.today {
            Section {
                HStack(spacing: 8) {
                    ForEach(choices(hasEntries: hasEntries), id: \.self) { choice in
                        Button {
                            model.setState(state == choice ? nil : choice, for: day)
                        } label: {
                            Text(choice.label).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(state == choice ? .accentColor : .secondary)
                        .buttonBorderShape(.capsule)
                    }
                }
            } header: {
                Text(day == model.today ? "Done logging today?" : "How complete is this day?")
            } footer: {
                Text("Complete days teach your maintenance estimate. Partly logged days are left out, never counted as eating less.")
            }
        }
    }

    func choices(hasEntries: Bool) -> [DayState] { hasEntries ? [.complete, .partial] : [.fasting, .partial] }
}
