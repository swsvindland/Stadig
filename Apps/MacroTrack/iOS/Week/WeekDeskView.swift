import NutritionEngine
import SwiftUI
import SystemCore

/// The week desk (the Mac, an iPad on its side): food planned in weeks, not days. Seven columns,
/// Monday to Sunday, each day's meals stacked toward its target under its calories and protein,
/// with today's now line and the days ahead drawn lighter; the selected day in the inspector; the
/// week's average day and the weight trend along the foot. A meal dragged to another day previews
/// both days and the week before it's let go, and moves as the Log tab's Move does, with its Undo.
struct WeekDeskView: View {
    /// Monday of the week on the desk.
    @State private var week = Day.today.startOfWeek
    @State private var selected = Day.today
    @State private var inspecting = true
    @State private var drag = WeekDrag()

    var body: some View {
        NavigationStack {
            // A minute at a time: today's now line moves, and food logged for later becomes eaten.
            TimelineView(.everyMinute) { context in
                WeekPage(now: context.date, week: $week, selected: $selected, inspecting: $inspecting, drag: drag)
            }
        }
    }
}

private struct WeekPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let now: Date
    @Binding var week: Day
    @Binding var selected: Day
    @Binding var inspecting: Bool
    let drag: WeekDrag
    @FocusState private var focused: Bool

    var body: some View {
        let board = model.weekBoard(week, now: now)
        let move = drag.held.flatMap { model.weekMove($0.meal, to: $0.day, week: week, now: now) }
        let shown = move?.after ?? board
        VStack(spacing: 0) {
            WideHeader(eyebrow: model.weekEyebrow(week), title: title) { buttons }
                .padding(.top, 8)
            WeekColumns(
                board: shown, now: now, move: move, selected: selected, drag: drag, select: select, open: open, moveMeal: moveMeal
            )
            .padding(.leading, 14)
            .padding(.trailing, 18)
            .padding(.top, 4)
            .overlay {
                if board.isEmpty { WeekEmpty(week: week, today: model.today) }
            }
            WeekFooter(average: shown.average, weight: model.weekWeight(week), units: model.units.weight)
                .padding(.leading, 14)
                .padding(.trailing, 18)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            step(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            step(1)
            return .handled
        }
        .onKeyPress(.return) {
            open(selected)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("week.desk")
        .sideInspector(isPresented: $inspecting, min: 300, ideal: 330, max: 400) {
            // Over another day, the day it would land on.
            if let day = shown.day(move?.to ?? selected) ?? shown.days.first {
                WeekInspector(day: day, board: shown, move: move, open: open)
            }
        }
        // The title, the week and its buttons are the page's own, as on the Log tab.
        .hidesNavigationBar()
        .inkGround()
        .onAppear {
            focused = true
            #if DEBUG
            holdForLaunch(board)
            #endif
        }
    }

    /// "Nov 9 – 15", or "Dec 28 – Jan 3" across a month.
    var title: String {
        (week.date()..<week.adding(days: 6).date()).formatted(.interval.month(.abbreviated).day())
    }

    @ViewBuilder
    var buttons: some View {
        if week != model.today.startOfWeek {
            Button("This Week") { show(week: model.today.startOfWeek) }
                .buttonStyle(.ghost)
                .accessibilityIdentifier("week.thisWeek")
        }
        CircleIconButton(symbol: "chevron.left", label: "Previous Week", identifier: "week.previous") { show(week: week.adding(weeks: -1)) }
            .help("The week before")
        CircleIconButton(symbol: "chevron.right", label: "Next Week", identifier: "week.next") { show(week: week.adding(weeks: 1)) }
            .help("The week after")
        CircleIconButton(symbol: "sidebar.trailing", label: inspecting ? "Hide Day" : "Show Day", identifier: "week.inspect") {
            inspecting.toggle()
        }
        .help(inspecting ? "Hide the day beside the week" : "Show the selected day beside the week")
    }

    func select(_ day: Day) {
        selected = day
        focused = true
    }

    /// The day in the Log tab: Return, or the inspector's button.
    func open(_ day: Day) { model.show(day: day) }

    /// The arrows: the day before or after, into the next week past Sunday.
    func step(_ days: Int) {
        let day = selected.adding(days: days)
        if day.startOfWeek != week { week = day.startOfWeek }
        selected = day
    }

    /// Another week, on the same weekday.
    func show(week other: Day) {
        selected = selected.adding(days: week.days(until: other))
        week = other
    }

    /// The Log tab's move, with ⌘Z for it in the window's Undo as well as the toast's.
    func moveMeal(_ meal: WeekMeal, to day: Day) {
        guard let undo = model.moveMeal(meal, to: day) else { return }
        selected = day
        undoManager?.registerUndo(withTarget: model) { model in model.undoMove(undo) }
        undoManager?.setActionName("Move \(meal.name)")
    }

    #if DEBUG
    /// -weekPreview 2 holds the week's last meal that moves, up to the selected day, over the day two
    /// days after its own, as a drag would, to see the preview without one.
    func holdForLaunch(_ board: WeekBoard) {
        guard let days = LaunchOptions.current.number(after: "-weekPreview"),
            let meal = board.days.filter({ $0.day <= selected }).reversed().lazy.compactMap({ $0.meals.last(where: \.canMove) }).first
        else { return }
        drag.start(meal)
        drag.over = meal.day.adding(days: days)
    }
    #endif
}

/// A week with nothing logged or planned in it, said calmly where the meals would be.
private struct WeekEmpty: View {
    @Environment(AppModel.self) private var model
    let week: Day
    let today: Day

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Ink.text)
            Text(detail).font(.subheadline).foregroundStyle(Ink.text3).multilineTextAlignment(.center)
            if week.adding(days: 6) >= today {
                Button("Meal Plan") { model.go(to: .mealPlan) }
                    .buttonStyle(.ghost)
                    .controlSize(.small)
                    .padding(.top, 4)
                    .accessibilityIdentifier("week.mealPlan")
            }
        }
        .frame(maxWidth: 320)
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("week.empty")
    }

    var title: String {
        if week.adding(days: 6) < today { return "Nothing logged this week" }
        return week > today ? "Nothing planned this week yet" : "Nothing logged or planned this week"
    }

    var detail: String {
        week.adding(days: 6) < today
            ? "Days you log show here, each meal stacked toward the day's target."
            : "Food you log ahead, and the meal plan's dishes, show here by day."
    }
}
