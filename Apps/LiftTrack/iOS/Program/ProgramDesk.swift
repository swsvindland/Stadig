import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// The block as the program desk (the Mac and iPad concept): its weeks across, each day's lifts down,
/// what each lift did or will do in each week, and the week running now lit. A lift selected opens
/// the inspector; ↑ and ↓ move the selection, S swaps it for the rest of the block.
struct ProgramDesk: View {
    @Environment(AppModel.self) private var model
    let mesocycle: Mesocycle
    /// The block running now: its weeks gone are done, the next session's column lit. A next block
    /// has none of that yet.
    let current: Bool
    let editable: Bool
    @Binding var selection: UUID?
    @State private var content: DeskContent?
    @State private var swapping: ProgramRow?
    @FocusState private var focused: Bool

    /// What the desk's numbers depend on: a change to any of it works them out again.
    private struct Key: Hashable {
        var mesocycle: Mesocycle
        var sessions: Int
        var latest: Date?
        var today: Day
        var avoid: Set<String>
        var unit: WeightUnit
        var current: Bool
    }

    var body: some View {
        ScrollView {
            if let content {
                VStack(alignment: .leading, spacing: 8) {
                    WeekHeader(content: content, layout: layout)
                    ForEach(content.days) { day in
                        DaySection(day: day, content: content, layout: layout, selection: $selection) { row in
                            rowMenu(row)
                        }
                    }
                    footer
                }
                .overlay(alignment: .topLeading) { litColumn(content) }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(characters: CharacterSet(charactersIn: "sS"), phases: .down) { _ in swapSelected() }
        .onAppear { focused = true }
        .task(id: key) { content = DeskContent(mesocycle: mesocycle, current: current, model: model) }
        .sheet(item: $swapping) { row in
            if let day = mesocycle.days.first(where: { $0.id == row.dayID }), let slot = day.slots.first(where: { $0.id == row.id }) {
                ProgramSwapSheet(mesocycle: mesocycle, dayID: day.id, slot: slot)
            }
        }
        .accessibilityIdentifier("program.desk")
    }

    private var key: Key {
        Key(
            mesocycle: mesocycle, sessions: model.sessions.count, latest: model.sessions.map(\.updatedAt).max(), today: model.today,
            avoid: model.settings.avoid, unit: model.gym.unit, current: current)
    }

    /// The lifts' names in a column of their own; the weeks share the rest evenly.
    private var layout: DeskLayout { DeskLayout(names: Platform.isMac ? 240 : 220, rowHeight: Platform.isMac ? 28 : 38) }

    /// The week running now, as a lit band down the whole desk, where that week's column falls.
    @ViewBuilder
    private func litColumn(_ content: DeskContent) -> some View {
        if let now = content.nowIndex {
            GeometryReader { geometry in
                let week = max(0, geometry.size.width - 12 - layout.names) / CGFloat(max(1, content.weeks.count))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.07))
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                    .frame(width: week, height: geometry.size.height + 8)
                    .offset(x: 6 + layout.names + week * CGFloat(now), y: -4)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(keys: ["↑", "↓"], label: "move")
            if editable { KeyHint(keys: ["S"], label: "swap") }
            KeyHint(keys: ["⌥⌘I"], label: "inspector")
            Spacer(minLength: 8)
            ForEach(SetRating.allCases, id: \.self) { rating in
                HStack(spacing: 5) {
                    Circle().fill(rating.color).frame(width: 7, height: 7)
                    Text(rating.label).font(.caption).foregroundStyle(Ink.text2)
                }
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 6)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func rowMenu(_ row: ProgramRow) -> some View {
        if editable && row.isStrength {
            Button("Swap for the Rest of the Block…", systemImage: "arrow.triangle.2.circlepath") { swapping = row }
        }
        Button("Show in Library", systemImage: "books.vertical") { model.show(inLibrary: row.exerciseID) }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard let order = content?.order, !order.isEmpty else { return .ignored }
        let index = selection.flatMap { order.firstIndex(of: $0) }
        let next = index.map { min(order.count - 1, max(0, $0 + step)) } ?? (step > 0 ? 0 : order.count - 1)
        selection = order[next]
        return .handled
    }

    private func swapSelected() -> KeyPress.Result {
        guard editable, let selection, let row = content?.row(selection), row.isStrength else { return .ignored }
        swapping = row
        return .handled
    }
}

/// The desk's names column and its rows' height: on the Mac a desk's, on the iPad a fingertip's.
struct DeskLayout {
    var names: CGFloat
    var rowHeight: CGFloat
}

/// Everything the desk shows, worked out off `body`: the weeks, and each day with its lifts across them.
struct DeskContent {
    struct Week: Identifiable {
        let id: Int
        let title: String
        let dates: String
        /// "Done", "Now", "Heaviest", "Deload".
        let state: String
        let load: Double
        let isNow: Bool
        let isDone: Bool
    }

    struct Lift: Identifiable {
        let row: ProgramRow
        let exercise: Exercise
        let cells: [ProgramLayout.LedgerCell]
        /// Each week's working sets against the slot's most: the small bars by the name.
        let volume: [Double]
        let score: Double?
        let estimateKg: Double?
        var id: UUID { row.id }
    }

    struct DeskDay: Identifiable {
        let id: UUID
        let name: String
        let caption: String
        let weeks: [ProgramLayout.LedgerDayWeek]
        /// "~57 min" for the next session.
        let nextMinutes: Int?
        let lifts: [Lift]
        /// Conditioning, with its minutes and zone the same every week.
        let conditioning: [ProgramRow]
        /// Warm-ups, drills, stretches and the sauna, by their block: a quiet line each.
        let extras: [(kind: SessionBlockKind, rows: [ProgramRow])]
    }

    let weeks: [Week]
    let days: [DeskDay]
    let unit: WeightUnit
    /// The lit column: the week running now, in the block running now.
    let nowIndex: Int?
    /// Every row in order, for ↑ and ↓.
    let order: [UUID]

    func row(_ id: UUID) -> ProgramRow? {
        for day in days {
            if let lift = day.lifts.first(where: { $0.id == id }) { return lift.row }
            if let row = day.conditioning.first(where: { $0.id == id }) { return row }
            if let row = day.extras.flatMap(\.rows).first(where: { $0.id == id }) { return row }
        }
        return nil
    }

    @MainActor
    init(mesocycle: Mesocycle, current: Bool, model: AppModel) {
        let block = mesocycle.block
        let today = model.today
        let weeks = ProgramLayout.weeks(of: block)
        let loads = ProgramLayout.weekLoads(mesocycle)
        let nowWeek = current ? block.week(of: today) : nil
        let heaviest = loads.indices.filter { !weeks[$0].isDeload }.max { loads[$0] < loads[$1] }
        let style = Date.FormatStyle.dateTime.day()
        let monthStyle = Date.FormatStyle.dateTime.day().month(.abbreviated)
        self.weeks = weeks.enumerated().map { index, week in
            let range: DayRange =
                if week.isDeload, let deload = block.deloadRange {
                    deload
                } else {
                    DayRange(
                        block.start.adding(weeks: index),
                        min(block.start.adding(weeks: index).adding(days: 6), block.effectiveDeloadStart.adding(days: -1)))
                }
            let isNow = week == nowWeek
            let isDone = current && range.end < today
            let state =
                isNow ? "Now" : isDone ? "Done" : week.isDeload ? "Deload" : index == heaviest ? "Heaviest" : ""
            return Week(
                id: index, title: week.isDeload ? "Deload" : "Week \(index + 1)",
                dates: "\(Format.day(range.start, style: style)) – \(Format.day(range.end, style: monthStyle))", state: state, load: loads[index],
                isNow: isNow, isDone: isDone)
        }
        nowIndex = weeks.firstIndex { $0 == nowWeek }
        unit = model.gym.unit

        let next = current ? model.plan() : nil
        let records = current ? model.sessions : []
        let strength = model.analysis?.strength
        let rows = ProgramRows.days(
            of: mesocycle, nextDayID: current ? model.analysis?.next?.day.id : nil, catalog: model.catalog, avoid: model.settings.avoid)
        var numbers: [String: (score: Double?, estimate: Double?)] = [:]
        var order: [UUID] = []
        days = zip(mesocycle.days, rows).map { day, laidOut in
            let slots = Dictionary(uniqueKeysWithValues: day.slots.map { ($0.id, $0) })
            let lifts: [Lift] = laidOut.rows.filter(\.isStrength).compactMap { row in
                guard let slot = slots[row.id] else { return nil }
                let exercise = model.catalog.resolve(slot.exerciseID)
                if numbers[exercise.id] == nil {
                    let record = model.record(for: exercise)
                    numbers[exercise.id] = (
                        strength.flatMap { record.score(for: exercise, bodyweightKg: $0.bodyweightKg, sex: $0.sex) }, record.current
                    )
                }
                let sets = ProgramLayout.setsByWeek(slot, block: block).map(\.sets)
                let most = Double(sets.max() ?? 1)
                return Lift(
                    row: row, exercise: exercise,
                    cells: ProgramLayout.ledger(slot: slot, day: day, of: mesocycle, records: records, next: next, today: today),
                    volume: sets.map { Double($0) / max(1, most) }, score: numbers[exercise.id]?.score, estimateKg: numbers[exercise.id]?.estimate)
            }
            let conditioning = laidOut.rows.filter { $0.blockKind == .conditioning }
            let others = laidOut.rows.filter { !$0.isStrength && $0.blockKind != .conditioning }
            var extras: [(kind: SessionBlockKind, rows: [ProgramRow])] = []
            for row in others {
                if let index = extras.firstIndex(where: { $0.kind == row.blockKind }) {
                    extras[index].rows.append(row)
                } else {
                    extras.append((row.blockKind, [row]))
                }
            }
            order += lifts.map(\.id) + conditioning.map(\.id) + extras.compactMap(\.rows.first?.id)
            let workSets = day.strengthSlots.map { $0.sets(week: 0) }.reduce(0, +)
            let isNext = next?.dayID == day.id
            return DeskDay(
                id: day.id, name: day.name,
                caption: "\(lifts.count) \(lifts.count == 1 ? "lift" : "lifts") · \(workSets) sets · ~\(day.minutes) min",
                weeks: ProgramLayout.ledger(day: day, of: mesocycle, records: records, next: next, today: today),
                nextMinutes: isNext ? next?.estimatedMinutes : nil, lifts: lifts, conditioning: conditioning, extras: extras)
        }
        self.order = order
    }
}

/// The weeks over the desk: the block's split, then each week with its dates, where it stands and a
/// thin ruler of how hard it is against the heaviest.
private struct WeekHeader: View {
    let content: DeskContent
    let layout: DeskLayout

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Spacer(minLength: 0)
                Text("Score").eyebrow().font(.system(size: 10, weight: .semibold))
            }
            .padding(.trailing, 10)
            .frame(width: layout.names, alignment: .leading)
            ForEach(content.weeks) { week in
                VStack(alignment: .leading, spacing: 7) {
                    ViewThatFits(in: .horizontal) {
                        weekLine(week, dates: true)
                        weekLine(week, dates: false)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(week.title).font(.system(size: 14, weight: .bold)).foregroundStyle(week.isDone ? Ink.text2 : Ink.text)
                            Text(week.state.isEmpty ? " " : week.state).font(.caption.weight(week.isNow ? .bold : .regular))
                                .foregroundStyle(week.isNow ? Color.accentColor : Ink.text3)
                        }
                        .lineLimit(1)
                    }
                    Ruler.thin(week.load, color: week.isNow ? .accentColor : (week.isDone ? Ink.text2 : Ink.text3.opacity(0.6)))
                }
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func weekLine(_ week: DeskContent.Week, dates: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(week.title).font(.system(size: 14, weight: .bold)).foregroundStyle(week.isDone ? Ink.text2 : Ink.text)
            if dates { Text(week.dates).font(.caption).foregroundStyle(Ink.text3) }
            Spacer(minLength: 2)
            Text(week.state).font(.caption.weight(week.isNow ? .bold : .regular))
                .foregroundStyle(week.isNow ? Color.accentColor : Ink.text3)
        }
        .lineLimit(1)
    }
}

/// A day of the block: its name and what's in it, when it was done each week, its lifts across the
/// weeks, and the rest of the day as quiet lines.
private struct DaySection<Menu: View>: View {
    @Environment(AppModel.self) private var model
    let day: DeskContent.DeskDay
    let content: DeskContent
    let layout: DeskLayout
    @Binding var selection: UUID?
    @ViewBuilder let menu: (ProgramRow) -> Menu

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            ForEach(day.lifts) { lift in
                LiftRow(lift: lift, content: content, layout: layout, selected: selection == lift.id)
                    .contentShape(.rect)
                    .onTapGesture { selection = lift.id }
                    .contextMenu { menu(lift.row) }
            }
            ForEach(day.conditioning) { row in
                QuietRow(row: row, layout: layout, selected: selection == row.id, cells: content.weeks.count)
                    .contentShape(.rect)
                    .onTapGesture { selection = row.id }
                    .contextMenu { menu(row) }
            }
            ForEach(day.extras, id: \.kind) { extra in
                ExtrasLine(kind: extra.kind, rows: extra.rows, selection: $selection)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 3)
        .padding(.bottom, 6)
        .background(.cardBackground, in: .rect(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(day.name)
    }

    private var heading: some View {
        HStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(day.name).font(.system(size: 15, weight: .bold)).tracking(-0.2).foregroundStyle(Ink.text).fixedSize()
                Text(day.caption).font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(width: layout.names, alignment: .leading)
            ForEach(Array(day.weeks.enumerated()), id: \.offset) { _, week in
                Group {
                    if let done = week.done {
                        Label(Format.day(done, style: .dateTime.weekday(.abbreviated).day()), systemImage: "checkmark")
                            .foregroundStyle(Ink.text3)
                    } else if week.isNext {
                        HStack(spacing: 6) {
                            Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                            Text(nextLabel).fontWeight(.bold)
                        }
                        .foregroundStyle(Color.accentColor)
                    } else if week.missed {
                        Text("Not done").foregroundStyle(Ink.text3)
                    }
                }
                .font(.caption)
                .labelStyle(DoneLabelStyle())
                .lineLimit(1)
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 30)
        .accessibilityElement(children: .combine)
    }

    /// "Tonight · ~57 min", or "Next · ~57 min" when it isn't today's.
    private var nextLabel: String {
        let today = model.analysis?.next?.scheduledToday == true
        let minutes = day.nextMinutes.map { " · ~\($0) min" } ?? ""
        return (today ? "Today" : "Next") + minutes
    }
}

private struct DoneLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10, weight: .bold)).foregroundStyle(Ink.good)
            configuration.title
        }
    }
}

/// A lift across the block: small bars of its sets each week, its name and score, then each week's
/// cell. Selected, it grows to show each week's load as a share of the estimated one-rep max.
private struct LiftRow: View {
    let lift: DeskContent.Lift
    let content: DeskContent
    let layout: DeskLayout
    let selected: Bool

    var body: some View {
        HStack(spacing: 0) {
            name
                .padding(.horizontal, 10)
                .frame(width: layout.names, alignment: .leading)
            ForEach(Array(lift.cells.enumerated()), id: \.offset) { _, cell in
                LedgerCellView(
                    cell: cell, exercise: lift.exercise, unit: content.unit, estimateKg: lift.estimateKg, selected: selected
                )
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: selected ? max(60, layout.rowHeight + 24) : layout.rowHeight)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.16))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("program.lift")
    }

    private var name: some View {
        HStack(spacing: 10) {
            VolumeBars(volume: lift.volume, nowIndex: content.nowIndex)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(lift.row.exercise)
                        .font(.system(size: selected ? 14.5 : 13, weight: selected ? .bold : .medium))
                        .foregroundStyle(lift.row.setAside ? Ink.text3 : Ink.text)
                        .lineLimit(1)
                    if !lift.row.superset.isEmpty {
                        Text(lift.row.superset).font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                            .help("Done in turn with the other \(lift.row.superset) slot of the day")
                    }
                    if lift.row.setAside {
                        Image(systemName: "nosign").font(.caption2).foregroundStyle(Ink.text3).help("Set aside: today's session swaps it out")
                            .accessibilityLabel("Set aside")
                    }
                }
                if selected, lift.estimateKg != nil {
                    Text("% of est. 1RM").font(.caption2).foregroundStyle(Ink.text3)
                }
            }
            Spacer(minLength: 4)
            if selected {
                Text("S").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Ink.text)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Color.accentColor.opacity(0.25), in: .rect(cornerRadius: 5))
                    .accessibilityHidden(true)
            }
            if let score = lift.score {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: selected ? 20 : 12.5, weight: selected ? .bold : .semibold)).monospacedDigit()
                    .foregroundStyle(selected ? Ink.text : Ink.text3)
                    .frame(minWidth: 26, alignment: .trailing)
                    .accessibilityLabel("Score \(Int(score.rounded()))")
            }
        }
    }
}

/// Four small bars: the lift's working sets each week, done ones grey, this week's in the accent.
private struct VolumeBars: View {
    let volume: [Double]
    let nowIndex: Int?

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(volume.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(index))
                    .frame(width: 5, height: max(4, 18 * value))
            }
        }
        .frame(width: 30, height: 18, alignment: .bottomLeading)
        .accessibilityHidden(true)
    }

    private func color(_ index: Int) -> Color {
        guard let nowIndex else { return Ink.text3.opacity(0.6) }
        if index < nowIndex { return Ink.text2 }
        return index == nowIndex ? .accentColor : Ink.text3.opacity(0.45)
    }
}

/// One lift in one week: sets × reps, the load, and how it went (the sets' ratings) or how it moved.
private struct LedgerCellView: View {
    let cell: ProgramLayout.LedgerCell
    let exercise: Exercise
    let unit: WeightUnit
    let estimateKg: Double?
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // On one line where the week has room (the Mac, an iPad on its side); in a narrow column,
            // the sets and reps over the load.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    setsAndRepsText.frame(width: cell.loadKg == nil && cell.seconds == nil ? nil : 50, alignment: .leading)
                    load
                    Spacer(minLength: 6)
                    trailing
                }
                VStack(alignment: .leading, spacing: 1) {
                    setsAndRepsText
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        load
                        Spacer(minLength: 4)
                        trailing
                    }
                }
            }
            if selected, let fraction {
                HStack(spacing: 8) {
                    Ruler(value: fraction, color: cell.state == .done ? Ink.text2 : .accentColor, height: 8)
                    Text(Format.percent(fraction)).font(.caption2).monospacedDigit().foregroundStyle(Ink.text3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var setsAndRepsText: some View {
        Text(setsAndReps)
            .font(.system(size: 12.5)).monospacedDigit()
            .foregroundStyle(cell.state == .done || cell.state == .missed ? Ink.text3 : Ink.text2)
            .lineLimit(1)
            .fixedSize()
    }

    private var setsAndReps: String {
        switch cell.state {
        case .missed where cell.sets == 0: "—"
        default: "\(cell.sets) × \(cell.reps)"
        }
    }

    @ViewBuilder
    private var load: some View {
        if let kg = cell.loadKg, exercise.loadBasis != .none {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if exercise.loadBasis == .bodyweightPlus && kg <= 0 {
                    Text("Body").font(.system(size: selected ? 20 : 14, weight: .bold))
                } else {
                    Text((exercise.loadBasis == .bodyweightPlus ? "+" : "") + Format.number(unit.fromKilograms(kg), digits: 2))
                        .font(.system(size: selected ? 20 : 14, weight: .bold)).monospacedDigit().tracking(-0.2)
                    Text(unit.symbol).font(.system(size: 11)).foregroundStyle(Ink.text3)
                }
            }
            .foregroundStyle(cell.state == .done ? Ink.text2 : Ink.text)
            .lineLimit(1)
            .fixedSize()
        } else if let seconds = cell.seconds {
            Text(Format.duration(seconds)).font(.system(size: 14, weight: .bold)).foregroundStyle(cell.state == .done ? Ink.text2 : Ink.text)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch cell.state {
        case .done:
            HStack(spacing: 3) {
                ForEach(Array(cell.ratings.enumerated()), id: \.offset) { _, rating in
                    Circle().fill(rating.color).frame(width: 6, height: 6)
                }
            }
        case .next:
            if let change = cell.changeKg {
                Text(changeText(change)).font(.system(size: 11.5, weight: change == 0 ? .regular : .semibold))
                    .foregroundStyle(change == 0 ? Ink.text3 : Ink.text2)
                    .fixedSize()
            }
        case .planned:
            EmptyView()
        case .missed:
            EmptyView()
        }
    }

    private func changeText(_ kg: Double) -> String {
        if abs(kg) < 0.01 { return "same" }
        return (kg > 0 ? "+" : "−") + Format.number(unit.fromKilograms(abs(kg)), digits: 2)
    }

    /// The load as a share of the estimated one-rep max, for a lift loaded as the estimate is.
    private var fraction: Double? {
        guard let kg = cell.loadKg, let estimateKg, estimateKg > 0, exercise.loadBasis == .external else { return nil }
        return kg / estimateKg
    }

    private var accessibilityText: String {
        var parts: [String] = []
        switch cell.state {
        case .done: parts.append("Done")
        case .next: parts.append("Next")
        case .planned: parts.append("Planned")
        case .missed: parts.append("Not done")
        }
        if cell.sets > 0 { parts.append("\(cell.sets) sets of \(cell.reps)") }
        if let kg = cell.loadKg { parts.append(Format.load(kg, unit: unit, basis: exercise.loadBasis)) }
        if !cell.ratings.isEmpty { parts.append(cell.ratings.map(\.label).joined(separator: ", ")) }
        if let change = cell.changeKg { parts.append(changeText(change)) }
        return parts.joined(separator: ", ")
    }
}

/// Conditioning across the block: the same minutes and zone each week.
private struct QuietRow: View {
    let row: ProgramRow
    let layout: DeskLayout
    let selected: Bool
    let cells: Int

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: row.blockKind.symbol).font(.caption).foregroundStyle(Ink.text3).frame(width: 30)
                Text(row.exercise).font(.system(size: 13, weight: selected ? .bold : .medium)).foregroundStyle(Ink.text).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(width: layout.names, alignment: .leading)
            ForEach(0..<cells, id: \.self) { _ in
                Text(row.sets).font(.system(size: 12.5)).foregroundStyle(Ink.text2).lineLimit(1)
                    .padding(.leading, 14)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: layout.rowHeight)
        .background {
            if selected { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.16)) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The warm-ups, drills, stretches or sauna of a day, in a line: each name selects its slot.
private struct ExtrasLine: View {
    let kind: SessionBlockKind
    let rows: [ProgramRow]
    @Binding var selection: UUID?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(kind.label).eyebrow().frame(width: 92, alignment: .leading)
            FlowLayout(spacing: 4) {
                ForEach(rows) { row in
                    Button {
                        selection = row.id
                    } label: {
                        Text(row.exercise)
                            .font(.caption.weight(selection == row.id ? .bold : .regular))
                            .foregroundStyle(selection == row.id ? Color.accentColor : Ink.text2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(selection == row.id ? Color.accentColor.opacity(0.16) : Ink.raised, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

/// A key and what it does, as the desk's foot lists them.
struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.text2)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 20)
                    .background(Ink.raised, in: .rect(cornerRadius: 5))
            }
            Text(label).font(.caption).foregroundStyle(Ink.text3)
        }
    }
}
