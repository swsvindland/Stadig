import NutritionEngine
import SwiftUI
import SystemCore
import UniformTypeIdentifiers

/// The seven columns under the kcal scale: each day's numbers over its meals, stacked from the top
/// toward the target line, a calorie to the same height in every column.
struct WeekColumns: View {
    let board: WeekBoard
    let now: Date
    let move: WeekMove?
    let selected: Day
    let drag: WeekDrag
    let select: (Day) -> Void
    let open: (Day) -> Void
    let moveMeal: @MainActor (WeekMeal, Day) -> Void

    /// The axis's room at the left, for the scale's numbers.
    static let axis: CGFloat = 46
    static let spacing: CGFloat = 8
    static let headerGap: CGFloat = 10

    @State private var height: CGFloat = 0
    @State private var headerHeight: CGFloat = 92

    var body: some View {
        let canvas = max(0, height - headerHeight - Self.headerGap)
        let scale = board.scaleTop > 0 ? canvas / board.scaleTop : 0
        ZStack(alignment: .topLeading) {
            WeekScale(board: board, scale: scale, top: headerHeight + Self.headerGap)
                .allowsHitTesting(false)
            HStack(alignment: .top, spacing: Self.spacing) {
                Color.clear.frame(width: Self.axis)
                ForEach(board.days) { day in
                    column(day, scale: scale)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            height = $0
        }
    }

    func column(_ day: WeekDay, scale: CGFloat) -> some View {
        let isSelected = move == nil && day.day == selected
        let isTarget = move?.to == day.day
        return VStack(alignment: .leading, spacing: Self.headerGap) {
            WeekDayHeader(day: day, before: move.flatMap { changed(day.day, in: $0) })
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    headerHeight = $0
                }
            WeekDayCanvas(
                day: day, board: board, now: now, scale: scale, move: move, drag: drag, days: board.days.map(\.day), open: open,
                moveMeal: moveMeal
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ColumnBackdrop(today: day.timing == .today, selected: isSelected, target: isTarget)
                .padding(.horizontal, -4)
        }
        .contentShape(.rect)
        .onTapGesture { select(day.day) }
        .onDrop(of: [.text], delegate: WeekDropTarget(day: day.day, drag: drag, drop: moveMeal))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Format.day(day.day, style: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("week.day")
    }

    /// The day as it was, for the two days a move changes.
    func changed(_ day: Day, in move: WeekMove) -> WeekDay? {
        day == move.to || day == move.from ? move.before.day(day) : nil
    }
}

/// Behind a column: today in the accent, the selected day outlined, and the day a meal is over in
/// the accent's outline.
private struct ColumnBackdrop: View {
    let today: Bool
    let selected: Bool
    let target: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        shape
            .fill(target ? Color.accentColor.opacity(0.08) : today ? Color.accentColor.opacity(0.055) : selected ? Ink.text.opacity(0.045) : .clear)
            .strokeBorder(target ? Color.accentColor.opacity(0.6) : selected ? Ink.text.opacity(0.1) : .clear, lineWidth: target ? 1.5 : 1)
    }
}

// MARK: - The scale

/// The kcal scale across the columns: a line every 500 up to the target, the target line, and
/// maintenance dashed below it ("Under this line you still lose").
private struct WeekScale: View {
    let board: WeekBoard
    /// Points per kcal.
    let scale: CGFloat
    /// Where the columns' meals start.
    let top: CGFloat

    var body: some View {
        let axis = WeekColumns.axis
        ZStack(alignment: .topLeading) {
            Text("kcal").eyebrow().frame(width: axis - 8, alignment: .trailing).offset(y: top + 2)
            ForEach(grid, id: \.self) { kcal in
                let y = top + kcal * scale
                Rectangle().fill(Ink.text.opacity(0.055)).frame(height: 1).padding(.leading, axis).offset(y: y)
                label(kcal, strong: false).offset(y: y - 7)
            }
            if let target = board.target {
                let y = top + target * scale
                Rectangle().fill(Ink.text.opacity(0.82)).frame(height: 2).padding(.leading, axis - 4).padding(.trailing, -6).offset(y: y - 1)
                label(target, strong: true).offset(y: y - 7)
                Text("Target").eyebrow(Ink.text).offset(x: axis + 10, y: y + 8)
            }
            if let maintenance = board.maintenance, maintenance < board.scaleTop {
                let y = top + maintenance * scale
                Line()
                    .stroke(Ink.text.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(height: 1.5)
                    .padding(.leading, axis - 4)
                    .padding(.trailing, -6)
                    .offset(y: y)
                label(maintenance, strong: false).offset(y: y - 7)
                HStack(spacing: 8) {
                    Text("Maintenance").eyebrow()
                    Text("Under this line you still lose.").font(.system(size: 11.5)).foregroundStyle(Ink.text3)
                }
                .lineLimit(1)
                .offset(x: axis + 10, y: y - 21)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// Every 500, below the target's line (or maintenance's) with room for its label.
    var grid: [Double] {
        let limit = (board.target ?? board.maintenance ?? board.scaleTop) - 120
        return stride(from: 500.0, to: max(500, limit), by: 500).map(\.self)
    }

    func label(_ kcal: Double, strong: Bool) -> some View {
        Text(Format.whole(kcal))
            .font(.system(size: 10.5, weight: strong ? .heavy : .semibold).monospacedDigit())
            .foregroundStyle(strong ? Ink.text : Ink.text3)
            .frame(width: WeekColumns.axis - 8, alignment: .trailing)
    }
}

/// A horizontal line through the middle of its frame, to stroke dashed.
nonisolated private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

// MARK: - A day's numbers

/// Over a column: the day, its calories against the target (what's left of it today) over a thin
/// ruler, and its protein over another. During a move, the two days it changes in the accent, with
/// what they were.
private struct WeekDayHeader: View {
    let day: WeekDay
    /// The day before the move, when the move changes it.
    let before: WeekDay?

    var body: some View {
        let target = day.target?.kcal
        let protein = day.target?.protein
        VStack(alignment: .leading, spacing: 5) {
            // "Today · Fri 13", or "Today" in a narrow column.
            ViewThatFits(in: .horizontal) {
                Text(eyebrow).eyebrow(day.timing == .today ? Color.accentColor : Ink.text3).fixedSize()
                Text(day.timing == .today ? "Today" : eyebrow).eyebrow(day.timing == .today ? Color.accentColor : Ink.text3).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(day.hasFood || day.timing == .today ? Format.whole(shownKcal) : "—")
                    .numeral(20)
                    .foregroundStyle(before != nil ? Color.accentColor : day.timing == .ahead || !day.hasFood ? Ink.text2 : Ink.text)
                // "28 under", or "−28" where that doesn't fit.
                ViewThatFits(in: .horizontal) {
                    Text(note).font(.system(size: 12)).foregroundStyle(noteColor).fixedSize()
                    // During a move, what it was, struck through.
                    if let before {
                        Text(Format.whole(before.total.kcal)).font(.system(size: 12)).strikethrough().foregroundStyle(Ink.text3).fixedSize()
                    } else {
                        Text(shortNote).font(.system(size: 12)).foregroundStyle(noteColor).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            WeekRuler(
                eaten: fraction(day.eaten.kcal, of: target), total: fraction(day.total.kcal, of: target), color: kcalColor,
                split: day.timing == .today && before == nil)
            ViewThatFits(in: .horizontal) {
                proteinLine(" g protein")
                proteinLine(" g")
            }
            .padding(.top, 3)
            WeekRuler(
                eaten: fraction(day.eaten.protein, of: protein), total: fraction(day.total.protein, of: protein), color: Ink.protein,
                split: day.timing == .today)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    func proteinLine(_ unit: String) -> some View {
        Text(
            "\(Text(Format.whole(shownProtein)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(day.timing == .past ? Ink.text : Ink.text2))\(Text(unit).font(.system(size: 11)).foregroundStyle(Ink.text3))"
        )
        .lineLimit(1)
        .fixedSize()
    }

    var eyebrow: String {
        let name = Format.day(day.day, style: .dateTime.weekday(.abbreviated).day())
        return day.timing == .today ? "Today · \(name)" : name
    }

    /// What's eaten today; everything on any other day.
    var shownKcal: Double { day.timing == .today && before == nil ? day.eaten.kcal : day.total.kcal }
    var shownProtein: Double { day.timing == .today && before == nil ? day.eaten.protein : day.total.protein }

    var note: String {
        if let before { return "was \(Format.whole(before.total.kcal))" }
        switch day.standing {
        case .left(let kcal): return "\(Format.whole(kcal)) left"
        case .under(let kcal): return "\(Format.whole(kcal)) under"
        case .over(let kcal): return "\(Format.whole(kcal)) over"
        case nil: return day.hasFood ? "" : day.timing == .past ? "Not logged" : "Nothing yet"
        }
    }

    var shortNote: String {
        guard before == nil else { return note }
        switch day.standing {
        case .left(let kcal): return Format.whole(kcal)
        case .under(let kcal): return "−\(Format.whole(kcal))"
        case .over(let kcal): return "+\(Format.whole(kcal))"
        case nil: return ""
        }
    }

    var noteColor: Color {
        if before != nil { return Ink.text3 }
        switch day.standing {
        case .over: return Ink.ok
        case .left: return Ink.text
        default: return Ink.text3
        }
    }

    var kcalColor: Color {
        if before != nil { return .accentColor }
        if case .over = day.standing, day.timing != .today { return Ink.ok }
        return day.timing == .ahead ? Color.accentColor.opacity(0.38) : .accentColor
    }

    func fraction(_ value: Double, of target: Double?) -> Double {
        guard let target, target > 0 else { return 0 }
        return value / target
    }

    var accessibilityText: String {
        var parts = [Format.day(day.day, style: .dateTime.weekday(.wide).day().month(.wide))]
        if day.hasFood || day.timing == .today {
            parts.append(day.timing == .today ? "\(Format.kcal(day.eaten.kcal)) eaten" : Format.kcal(day.total.kcal))
        }
        if !note.isEmpty { parts.append(note) }
        if day.hasFood { parts.append("\(Format.grams(day.total.protein)) protein") }
        return parts.joined(separator: ", ")
    }
}

/// A thin ruler; today's shows what's eaten in full and what's still to come lighter behind it.
private struct WeekRuler: View {
    let eaten: Double
    let total: Double
    let color: Color
    let split: Bool

    var body: some View {
        if split {
            Ruler.thin(total, color: color.opacity(0.4))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        let width = proxy.size.width * min(1, max(0, eaten))
                        RoundedRectangle(cornerRadius: 1.8, style: .continuous).fill(color).frame(width: eaten > 0 ? max(3, width) : 0)
                    }
                }
        } else {
            Ruler.thin(total, color: color)
        }
    }
}

// MARK: - A day's meals

/// A column's meals, each as tall as its calories (a little more for a small one, to read), one
/// under the next; the part past the target tinted; today's now line under what's eaten.
private struct WeekDayCanvas: View {
    let day: WeekDay
    let board: WeekBoard
    let now: Date
    let scale: CGFloat
    let move: WeekMove?
    let drag: WeekDrag
    let days: [Day]
    let open: (Day) -> Void
    let moveMeal: @MainActor (WeekMeal, Day) -> Void

    static let gap: CGFloat = 3

    var body: some View {
        let placed = Self.place(day.meals, scale: scale)
        ZStack(alignment: .top) {
            ForEach(placed, id: \.meal.id) { item in
                block(item)
            }
            if let over = overTarget(placed) {
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
                    .fill(Ink.ok.opacity(0.16))
                    .frame(height: over.height)
                    .overlay(alignment: .bottomTrailing) {
                        if over.height >= 18 {
                            Text("\(Format.whole(over.kcal)) over").font(.system(size: 11, weight: .bold)).foregroundStyle(Ink.ok).padding(6)
                        }
                    }
                    .offset(y: over.top)
                    .allowsHitTesting(false)
            }
            if day.timing == .today, move == nil {
                NowLine(time: Format.time(now))
                    .offset(y: nowY(placed) - 4)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    func block(_ item: Placed) -> some View {
        let meal = item.meal
        let moving = move?.holdsMoved(meal) ?? false
        let lifted = drag.meal?.id == meal.id && drag.over != nil
        // The drag and the menu on the block, then the block where it goes: what's held is what's seen.
        return WeekMealBlock(
            meal: meal, height: item.height, style: moving ? .landing : meal.isAhead ? .ahead : .eaten, from: moving ? move?.from : nil
        )
        .modifier(MealActions(meal: meal, height: item.height, days: days, drag: drag, open: open, moveMeal: moveMeal))
        .opacity(lifted ? 0.35 : 1)
        .offset(y: item.top)
    }

    /// The tint from the day's own target line to the foot of its meals.
    func overTarget(_ placed: [Placed]) -> (top: CGFloat, height: CGFloat, kcal: Double)? {
        guard let target = day.target?.kcal, target > 0, day.total.kcal > target, let last = placed.last else { return nil }
        let top = target * scale
        let bottom = last.top + last.height
        guard bottom > top else { return nil }
        return (top, bottom - top, day.total.kcal - target)
    }

    /// Under the last meal eaten, or at the top before the first.
    func nowY(_ placed: [Placed]) -> CGFloat {
        let eaten = day.eatenMeals
        guard eaten > 0, eaten <= placed.count else { return 0 }
        let last = placed[eaten - 1]
        return last.top + last.height + Self.gap / 2
    }

    struct Placed {
        let meal: WeekMeal
        let top: CGFloat
        let height: CGFloat
    }

    /// Each meal at the height of the calories before it, as tall as its own (less the gap
    /// between), never shorter than a line of type: a small one pushes the rest down a little.
    static func place(_ meals: [WeekMeal], scale: CGFloat, minimum: CGFloat = 22) -> [Placed] {
        var placed: [Placed] = []
        var kcal = 0.0
        var bottom = -gap
        for meal in meals {
            let top = max(kcal * scale, bottom + gap)
            let height = max(minimum, meal.nutrients.kcal * scale - gap)
            placed.append(Placed(meal: meal, top: top, height: height))
            kcal += meal.nutrients.kcal
            bottom = top + height
        }
        return placed
    }
}

/// Today's now line: across the column and a little past it, a dot at its start, and the time.
private struct NowLine: View {
    let time: String

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.accentColor).frame(height: 2).padding(.horizontal, -4)
            Circle().fill(Color.accentColor).frame(width: 8, height: 8).offset(x: -7)
            // Above the line, in the corner of the last meal eaten (or over the column's top before
            // the first), where a block keeps nothing.
            Text("Now \(time)")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .background(Ink.ground, in: .capsule)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(y: -11)
        }
        .frame(height: 8)
    }
}

/// What a meal on the desk does: drags to another day if it's in the log (a dish on the plan moves
/// in the meal plan), and has the same in its context menu and as accessibility actions.
private struct MealActions: ViewModifier {
    @Environment(AppModel.self) private var model
    let meal: WeekMeal
    let height: CGFloat
    let days: [Day]
    let drag: WeekDrag
    let open: (Day) -> Void
    let moveMeal: @MainActor (WeekMeal, Day) -> Void

    func body(content: Content) -> some View {
        if meal.canMove {
            content
                .onDrag {
                    drag.start(meal)
                    return NSItemProvider(object: meal.id as NSString)
                } preview: {
                    WeekMealBlock(meal: meal, height: height, style: .lifted, from: nil).frame(width: 150)
                }
                .contextMenu { menu }
                .accessibilityActions {
                    ForEach(others, id: \.self) { day in
                        Button("Move to \(name(day))") { moveMeal(meal, day) }
                    }
                }
        } else {
            content.contextMenu {
                Button("Show in Meal Plan", systemImage: "takeoutbag.and.cup.and.straw") { model.go(to: .mealPlan) }
                Button("Show in Log", systemImage: "list.bullet.clipboard") { open(meal.day) }
            }
        }
    }

    @ViewBuilder
    var menu: some View {
        Menu("Move to", systemImage: "arrow.right") {
            ForEach(others, id: \.self) { day in
                Button(name(day)) { moveMeal(meal, day) }
            }
        }
        Button("Show in Log", systemImage: "list.bullet.clipboard") { open(meal.day) }
    }

    var others: [Day] { days.filter { $0 != meal.day } }

    func name(_ day: Day) -> String { Format.day(day, style: .dateTime.weekday(.wide).day()) }
}

// MARK: - A meal

/// A meal as a block on the desk: its time and calories, its name, its foods' markers and its
/// protein, as much of that as its height has room for. What's still to come is drawn as an
/// outline, lighter; a meal landing on a day during a move, in the accent.
struct WeekMealBlock: View {
    enum Style { case eaten, ahead, landing, lifted }

    let meal: WeekMeal
    let height: CGFloat
    let style: Style
    /// During a move, the day it comes from.
    let from: Day?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // "12:30 PM" where there's room, "12:30" in a narrow column.
                ViewThatFits(in: .horizontal) {
                    time(Format.time(meal.start))
                    time(meal.start.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                    Color.clear.frame(width: 0, height: 0)
                }
                Spacer(minLength: 2)
                Text(Format.whole(meal.nutrients.kcal))
                    .font(.system(size: 12.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(strong)
                    .fixedSize()
            }
            if height >= 40 {
                // A second line in a narrow column (an iPad with the sidebar out), where the block has
                // the height for it beside the markers, rather than "Chicken a…".
                Text(meal.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(strong)
                    .lineLimit(height >= 86 || (height >= 56 && height < 70) ? 2 : 1)
            }
            if height >= 70, !meal.markers.isEmpty {
                // As many as the column has room for.
                ViewThatFits(in: .horizontal) {
                    markers(4)
                    markers(3)
                    markers(2)
                    markers(1)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            if height >= 100 || (from != nil && height >= 56) {
                HStack {
                    Text("\(Format.whole(meal.nutrients.protein)) P").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.protein)
                    Spacer(minLength: 4)
                    if let from {
                        Text("from \(Format.day(from, style: .dateTime.weekday(.abbreviated)))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.text2)
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, height >= 40 ? 6 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
        .background(fill, in: shape)
        .overlay {
            switch style {
            case .ahead: shape.strokeBorder(Ink.text.opacity(0.13), lineWidth: 1)
            case .landing, .lifted: shape.strokeBorder(Color.accentColor, lineWidth: 1.5)
            case .eaten: EmptyView()
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(meal.canMove ? "Drag to another day to move it" : "")
        .accessibilityIdentifier("week.meal")
    }

    var strong: Color { style == .ahead ? Ink.text2 : Ink.text }

    func time(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(style == .lifted ? Ink.text2 : Ink.text3)
            .lineLimit(1)
            .fixedSize()
    }

    func markers(_ count: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(meal.markers.prefix(count), id: \.self) { marker in
                Text(marker)
                    .font(.system(size: 12))
                    .frame(width: 20, height: 20)
                    .background(markerFill, in: .rect(cornerRadius: 6, style: .continuous))
                    .opacity(style == .ahead ? 0.72 : 1)
            }
        }
    }

    var fill: Color {
        switch style {
        case .eaten: .cardBackground
        case .ahead: .clear
        case .landing: Color.accentColor.opacity(0.14)
        case .lifted: Ink.raised
        }
    }

    var markerFill: Color { style == .ahead ? Ink.text.opacity(0.055) : style == .lifted ? Ink.text.opacity(0.09) : Ink.raised }

    var accessibilityText: String {
        let when =
            switch meal.kind {
            case .eaten: Format.time(meal.start)
            case .later: "\(Format.time(meal.start)), later"
            case .planned: "\(Format.time(meal.start)), on the meal plan"
            }
        return "\(meal.name), \(when), \(Format.kcal(meal.nutrients.kcal)), \(Format.grams(meal.nutrients.protein)) protein"
    }
}
