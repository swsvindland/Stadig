import HubEngine
import SwiftUI
import SystemCore

/// The day: what's next, over its six parts. Nothing here is ticked off. What the apps track fills in
/// as it's logged there, and everything else passes by itself.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isToday: Bool { model.selectedDay == model.today }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if Platform.isVision, let day = model.shownDay {
                        Text(HubText.summary(day)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    DayChips()
                    if let day = model.shownDay {
                        if let note = HubText.note(on: day.day, changes: model.changes) {
                            Text(note)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(HubItem.Kind.study.color.opacity(0.14), in: .rect(cornerRadius: 14))
                                .accessibilityIdentifier("today.note")
                        }
                        if !day.isKnown {
                            Text("Your schedule stops before this day, so this is a guess at it.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if isToday { NowCard(item: HubPlanner.next(in: day, at: model.part), part: model.part) }
                        CardColumns {
                            ForEach(day.parts) { part in
                                PartCard(part: part, isEarlier: isToday && part.part < model.part)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .pageWidth(sizeClass)
            }
            .background(.pageBackground)
            .navigationTitle(model.selectedDay.weekday.name)
            .navigationSubtitleIfAvailable(model.shownDay.map(HubText.summary) ?? "")
            .toolbar {
                ToolbarItem(placement: .barTrailing) {
                    Button("Plans changed") { model.showPlansChanged = true }
                        .accessibilityIdentifier("today.plansChanged")
                }
            }
        }
    }
}

/// The week's days, to look at another one.
struct DayChips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { offset in
                let day = model.today.startOfWeek.adding(days: offset)
                let selected = day == model.selectedDay
                Button {
                    model.selectedDay = day
                } label: {
                    Text(day.weekday.short)
                        .font(.footnote.weight(day == model.today ? .bold : .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selected ? AnyShapeStyle(Color.strongFill) : AnyShapeStyle(.cardBackground), in: .rect(cornerRadius: 12))
                        .foregroundStyle(selected ? AnyShapeStyle(Color.onStrongFill) : AnyShapeStyle(.primary))
                }
                .buttonStyle(.plain)
                .hoverable(in: .rect(cornerRadius: 12))
                .accessibilityLabel(day.weekday.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("today.day.\(day.weekday.short)")
            }
        }
    }
}

/// What's next, and the app that does it.
struct NowCard: View {
    let item: HubItem?
    let part: DayPart

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let item {
                Text(HubText.heading(item, at: part))
                    .font(.footnote.weight(.semibold))
                    .opacity(0.75)
                Text(item.title)
                    .font(.title.bold())
                    .accessibilityIdentifier("today.next")
                Text(HubText.length(item.minutes))
                    .font(.subheadline)
                    .opacity(0.75)
                if let app = item.app, let action = item.action {
                    OpenAppButton(app: app) {
                        Text(action)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.onStrongFill, in: .capsule)
                            .foregroundStyle(Color.strongFill)
                    }
                    .buttonStyle(.plain)
                    .hoverable(in: .capsule)
                    .padding(.top, 6)
                    .accessibilityIdentifier("today.open")
                }
            } else {
                Text("The rest of the day is yours")
                    .font(.title3.bold())
                    .accessibilityIdentifier("today.next")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.strongFill, in: .rect(cornerRadius: 22))
        .foregroundStyle(Color.onStrongFill)
    }
}

/// A part of the day and what's in it.
struct PartCard: View {
    let part: HubPart
    let isEarlier: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(part.part.label).font(.subheadline.weight(.bold))
                Spacer()
                Text(HubText.status(part, isEarlier: isEarlier))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 28)
            .accessibilityElement(children: .combine)
            if !isEarlier {
                ForEach(part.items) { item in
                    ItemRow(item: item)
                }
            }
        }
        .card(padding: 12, radius: 18)
        .accessibilityIdentifier("today.part.\(part.part.rawValue)")
    }
}

/// One thing in a part. What an app tracks opens that app, a class opens the move sheet, and the gym
/// does the first with a button beside it for the second. The rest has nothing to tap.
struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: HubItem

    var body: some View {
        if let app = item.app {
            HStack(spacing: 6) {
                OpenAppButton(app: app) {
                    row(trailing: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint(item.action ?? "")
                .accessibilityIdentifier("today.item.\(item.id)")
                if item.canMove {
                    Button {
                        model.moving = item
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.footnote)
                            .frame(width: 44, height: 36)
                            .background(.insetBackground, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Move \(item.title)")
                    .accessibilityIdentifier("today.move.\(item.id)")
                }
            }
        } else if item.canMove {
            Button {
                model.moving = item
            } label: {
                row(trailing: false, moves: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Move it to another part of the day")
            .accessibilityIdentifier("today.move.\(item.id)")
        } else {
            row(trailing: false)
        }
    }

    private func row(trailing: Bool, moves: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.done ? .secondary : .primary)
            Spacer()
            if item.done {
                Image(systemName: "checkmark").foregroundStyle(.secondary).accessibilityLabel("Done")
            } else {
                Text(moves ? "\(HubText.length(item.minutes)) · Move" : HubText.length(item.minutes)).font(.footnote).foregroundStyle(.secondary)
                if trailing { Image(systemName: "arrow.up.forward").font(.footnote).foregroundStyle(.secondary).accessibilityHidden(true) }
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .background(item.kind.color.opacity(0.14), in: .rect(cornerRadius: 10))
        .contentShape(.rect(cornerRadius: 10))
    }
}

/// One tap for when the week isn't going to go as it looks. Neither asks why, and doing nothing is
/// just as fine: whatever doesn't happen moves on by itself.
struct PlansChangedView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                choice("I'm out tonight", "Clears the evening and night. No reason needed.", identifier: "plans.out") {
                    model.outTonight()
                }
                .disabled(model.isOutTonight)
                choice(
                    model.isLighter ? "Back to a full week" : "Lighter week", "Fewer study blocks and a shorter gym session. Ends Sunday.",
                    identifier: "plans.lighter"
                ) {
                    model.toggleLighterWeek()
                }
                Spacer(minLength: 0)
                if model.isOutTonight || model.isLighter {
                    Button("Back to the plan as it was") {
                        model.backToPlan()
                        dismiss()
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("plans.reset")
                }
            }
            .padding(16)
            .navigationTitle("Plans changed?")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .sheetForm(width: 420, height: 340)
    }

    private func choice(_ title: String, _ detail: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(14)
            .background(.insetBackground, in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
