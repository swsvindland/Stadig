import NutritionEngine
import SwiftUI
import SystemCore

/// What can be done with the foods picked out, in the bar above the tabs: how many, whether they're
/// moving or copying, and where to. With the tab bar minimised there's less room, so the targets
/// fold into a menu.
struct SelectionBar: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    #endif
    @State private var choosingDates = false

    var isInline: Bool {
        #if os(iOS)
        placement == .inline
        #else
        false
        #endif
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 4) {
            Button {
                model.clearSelection()
            } label: {
                Label("\(model.selection.ids.count)", systemImage: "xmark").labelStyle(.titleAndIcon).font(
                    .subheadline.weight(.semibold).monospacedDigit()
                )
                .padding(.leading, 12).frame(height: 40).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(model.selection.ids.count) selected. Clear")
            .accessibilityIdentifier("selection.clear")
            Button {
                model.selection.intent = model.selection.intent == .move ? .copy : .move
            } label: {
                Text(model.selection.intent == .move ? "Move" : "Copy").font(.subheadline.weight(.semibold)).frame(minWidth: 46, minHeight: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityHint("Switches between moving and copying")
            .accessibilityIdentifier("selection.intent")
            Spacer(minLength: 0)
            if isInline {
                Menu {
                    targets
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 40, height: 40)
                }
                .accessibilityLabel("Where to")
                .accessibilityIdentifier("selection.targets")
            } else {
                targets
            }
            Button {
                choosingDates = true
            } label: {
                Image(systemName: "calendar").frame(width: 34, height: 40).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("To Dates")
            .accessibilityIdentifier("selection.dates")
            Button {
                model.deleteSelection()
            } label: {
                Image(systemName: "trash").frame(width: 34, height: 40).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .accessibilityLabel("Delete")
            .accessibilityIdentifier("selection.delete")
            .padding(.trailing, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selection.bar")
        .sheet(isPresented: $choosingDates) { ToDatesSheet().macSheetSize(width: 380, height: 460) }
        .notesWork(choosingDates)
    }

    @ViewBuilder
    var targets: some View {
        target("Now", id: "now") { model.placeSelection(.now(Date()), named: "now") }
        target("Today", id: "today") { model.placeSelection(.sameTimes(on: model.today), named: "today") }
        target("Tmrw", id: "tomorrow", label: "Tomorrow") { model.placeSelection(.sameTimes(on: model.today.adding(days: 1)), named: "tomorrow") }
    }

    func target(_ title: String, id: String, label: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline).lineLimit(1).frame(minWidth: 40, minHeight: 40).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("To \(label ?? title)")
        .accessibilityIdentifier("selection.to.\(id)")
    }
}

/// Days to take the selection to: a month of them, any number picked. It's drawn here because the
/// system's multi-date picker isn't on the Mac.
struct ToDatesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<Day> = []
    /// Some day of the month shown.
    @State private var month: Day = .today

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack {
                    Button("Previous Month", systemImage: "chevron.left") { month = Self.first(of: month).adding(days: -1) }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("toDates.previousMonth")
                    Spacer()
                    Text(month.date().formatted(.dateTime.month(.wide).year())).font(.headline)
                    Spacer()
                    Button("Next Month", systemImage: "chevron.right") { month = Self.first(of: month).adding(days: 32) }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("toDates.nextMonth")
                }
                .buttonStyle(.borderless)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                    ForEach(Array(Self.weekdayNames.enumerated()), id: \.offset) { _, name in
                        Text(name).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(0..<Self.leadingBlanks(month), id: \.self) { _ in Color.clear.frame(height: 1) }
                    ForEach(Self.days(in: month), id: \.self) { day in
                        dayButton(day)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(model.selection.intent == .move ? "Move to" : "Copy to")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("toDates.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(days.count > 1 ? "\(days.count) Days" : "Done") {
                        model.placeSelection(on: Array(days))
                        dismiss()
                    }
                    .disabled(days.isEmpty)
                    .accessibilityIdentifier("toDates.done")
                }
            }
        }
        .presentationDetents([.height(480)])
    }

    func dayButton(_ day: Day) -> some View {
        let picked = days.contains(day)
        return Button {
            if days.remove(day) == nil { days.insert(day) }
        } label: {
            Text("\(day.dayOfMonth)")
                .font(.subheadline.monospacedDigit().weight(picked ? .bold : .regular))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(picked ? Color.accentColor.opacity(0.25) : .clear, in: .circle)
                .overlay {
                    if day == model.today { Circle().strokeBorder(Color.accentColor, lineWidth: 1) }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Format.day(day, style: .dateTime.weekday(.wide).month().day()))
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("toDates.day")
    }

    static func first(of month: Day) -> Day { month.adding(days: 1 - month.dayOfMonth) }

    static func days(in month: Day) -> [Day] {
        let first = first(of: month)
        var days: [Day] = []
        var day = first
        while day.month == first.month {
            days.append(day)
            day = day.adding(days: 1)
        }
        return days
    }

    /// Empty cells before the 1st, by the person's first day of the week.
    static func leadingBlanks(_ month: Day, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: first(of: month).date())
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    static var weekdayNames: [String] {
        let calendar = Calendar.current
        let names = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { names[(calendar.firstWeekday - 1 + $0) % 7] }
    }
}
