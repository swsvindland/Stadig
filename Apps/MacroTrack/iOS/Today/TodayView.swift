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
                WeightSection(day: model.selectedDay)
                if model.selectedDay == model.today {
                    ActionsSection()
                    if !model.logAgain.isEmpty || model.usualNow != nil { LogAgainSection() }
                } else {
                    Section {
                        Label("Catching up \(Format.relative(model.selectedDay, today: model.today)). New entries land on that day.",
                              systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                    }
                }
                TimelineSections(day: model.selectedDay, editing: $editing)
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

/// The prescriptive cards: what was seen, and the one thing to do.
struct ActionsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let analysis = model.analysis {
            let actions = analysis.actions.filter { $0.kind != .weighIn }.prefix(2)
            let checkIn = recentCheckIn
            if !actions.isEmpty || checkIn != nil {
                Section {
                    if let checkIn { CheckInRow(checkIn: checkIn, previous: model.checkIns.last { $0.day < checkIn.day }) }
                    ForEach(Array(actions)) { action in
                        ActionRow(action: action)
                    }
                }
            }
        }
    }

    /// This week's check-in, for a couple of days after it moved the targets.
    var recentCheckIn: CheckIn? {
        guard let last = model.checkIns.last, last.day.days(until: model.today) <= 2, model.checkIns.count > 1 else { return nil }
        return last
    }
}

/// The day's weight, always one tap away: a field to weigh in, or the reading and the trend.
struct WeightSection: View {
    @Environment(AppModel.self) private var model
    let day: Day
    @State private var weight = ""
    @FocusState private var focused: Bool

    var body: some View {
        let unit = model.units.weight
        let reading = model.weighIns.last { $0.day == day && !$0.excluded }
        let away = day == model.today && (model.analysis.map { $0.targets.mode == .vacation || $0.targets.mode == .illness } ?? false)
        if reading != nil || !away {
            Section {
                if let reading {
                    Button {
                        model.showWeighIn = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "scalemass").foregroundStyle(Color.accentColor).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Format.weight(reading.kg, unit: unit)).font(.subheadline.weight(.semibold).monospacedDigit())
                                if let trend = model.analysis?.trend[day] {
                                    Text("Trend \(Format.weight(trend, unit: unit))\(change.map { " · \($0)" } ?? "")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if case .health = reading.source { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink) }
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Weight \(Format.weight(reading.kg, unit: unit)). Edit weigh-ins")
                } else {
                    field(unit)
                }
            }
        }
    }

    var change: String? {
        guard day == model.today, let weekly = model.analysis?.weeklyChange else { return nil }
        return Format.weeklyChange(weekly, unit: model.units.weight)
    }

    /// A weigh-in in one field and one tap.
    func field(_ unit: WeightUnit) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "scalemass").foregroundStyle(Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Weigh in").font(.subheadline.weight(.semibold))
                Text(day == model.today ? "First thing, after the bathroom" : Format.day(day)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TextField(model.latestWeighIn.map { Format.number(unit.fromKilograms($0.kg)) } ?? "0.0", text: $weight)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(width: 70)
                .focused($focused)
            Text(unit.symbol).foregroundStyle(.secondary)
            Button("Save") { save(unit) }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(parsed(unit) == nil)
        }
    }

    func parsed(_ unit: WeightUnit) -> Double? {
        guard let value = Double(weight.replacingOccurrences(of: ",", with: ".")), value > 20 else { return nil }
        return unit.toKilograms(value)
    }

    func save(_ unit: WeightUnit) {
        guard let kg = parsed(unit) else { return }
        focused = false
        weight = ""
        model.weighIn(kg: kg, date: day == model.today ? Date() : day.date().addingTimeInterval(7 * 3600))
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

/// What's worth logging again right now, one tap each: what was eaten around now yesterday,
/// then single foods by how often and how recently they're eaten at this time of day.
struct LogAgainSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if let usual = model.usualNow {
                        chip(title: "Same as \(Format.relative(Day(usual.start), today: model.today))",
                             detail: "\(Format.time(usual.start)) · \(usual.entries.map(\.name).prefix(2).joined(separator: ", "))\(usual.entries.count > 2 ? " +\(usual.entries.count - 2)" : "")",
                             kcal: usual.nutrients.kcal, highlight: true) {
                            model.logAgain(usual)
                        }
                        .accessibilityLabel("Log the same as \(Format.relative(Day(usual.start), today: model.today)): \(usual.entries.map(\.name).joined(separator: ", ")), \(Format.kcal(usual.nutrients.kcal))")
                    }
                    ForEach(model.logAgain.prefix(10)) { item in
                        chip(title: item.template.name, detail: item.template.amountLabel, kcal: item.template.nutrients.kcal) {
                            model.logAgain(item)
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

    func chip(title: String, detail: String, kcal: Double, highlight: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(detail) · \(Format.whole(kcal))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: 180, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(highlight ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(.insetBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// The day as a timeline: each moment (foods eaten together) with its time and total.
struct TimelineSections: View {
    @Environment(AppModel.self) private var model
    let day: Day
    @Binding var editing: FoodEntry?

    var body: some View {
        let moments = Timeline.moments(model.entries(on: day))
        if moments.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day == model.today ? "Nothing logged yet today" : "Nothing logged on this day").font(.subheadline.weight(.semibold))
                    Text("Search, scan, snap or describe below. Foods eaten together are kept together, however many times you eat.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        ForEach(moments) { moment in
            MomentSection(moment: moment, editing: $editing)
        }
    }
}

/// Foods eaten together: their time, their total, and quick ways to add to them or eat them again.
struct MomentSection: View {
    @Environment(AppModel.self) private var model
    let moment: Moment
    @Binding var editing: FoodEntry?

    var body: some View {
        Section {
            ForEach(moment.entries) { entry in
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
                        model.log([LogAgain.copy(entry, to: model.logDate(), source: .copied)])
                    }
                    .tint(.accentColor)
                }
            }
        } header: {
            HStack(spacing: 10) {
                Text(Format.time(moment.start)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                Text(Format.kcal(moment.nutrients.kcal)).monospacedDigit()
                Menu {
                    Button("Log all again", systemImage: "arrow.clockwise") { model.logAgain(moment) }
                    Button("Delete all", systemImage: "trash", role: .destructive) { model.delete(entries: moment.entries.map(\.id)) }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .accessibilityLabel("More for \(Format.time(moment.start))")
                Button {
                    // Added foods join this moment.
                    model.loggerTime = moment.end.addingTimeInterval(60)
                    model.logger = .search
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityLabel("Add to \(Format.time(moment.start))")
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
