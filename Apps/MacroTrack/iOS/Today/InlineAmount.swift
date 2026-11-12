import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// A food on Today's thread opened in place: its amount in big numerals between − and +, a ruler to
/// drag it along, half to double as chips, and Delete. Done (or closing it any other way) saves the
/// new amount once, with an Undo; More opens the full amount panel for units, the time and the
/// rest. The numbers update as the amount moves.
struct InlineAmount: View {
    @Environment(AppModel.self) private var model
    let entry: FoodEntry
    let close: () -> Void
    /// The full amount panel, with the entry as this left it.
    let more: (FoodEntry) -> Void
    @State private var draft = AmountDraft()
    @State private var count = 0.0
    @State private var opened = false

    var body: some View {
        let unit = draft.amount.unit
        let preview = unit.map { model.rescaled(entry, food: draft.food, unit: $0, count: count) } ?? entry
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                FoodTile(name: entry.name, size: TileSize.header, fill: Ink.raised)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.headline).foregroundStyle(Ink.text).lineLimit(1)
                    Text(
                        "\(Format.kcal(preview.nutrients.kcal)) · \(Format.whole(preview.nutrients.protein)) P · \(Format.whole(preview.nutrients.carbs)) C · \(Format.whole(preview.nutrients.fat)) F"
                    )
                    .font(.caption.monospacedDigit()).foregroundStyle(Ink.text2).lineLimit(1)
                    .contentTransition(.numericText())
                }
                Spacer(minLength: 4)
                Button("Done", action: finish)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("today.amount.done")
            }
            if let unit {
                HStack {
                    step("Less", "minus", -FoodUnits.step(for: unit), unit: unit)
                    Spacer()
                    Measure(
                        value: FoodUnits.format(count, unit),
                        unit: String(FoodUnits.label(count: count, unit: unit).dropFirst(FoodUnits.format(count, unit).count + 1)),
                        size: 44
                    )
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("today.amount.value")
                    Spacer()
                    step("More", "plus", FoodUnits.step(for: unit), unit: unit)
                }
                slider(unit)
                HStack(spacing: 6) {
                    ForEach(choices(unit), id: \.self) { value in
                        Button(AmountChoices.label(value, unit: unit)) { set(value, unit: unit) }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(abs(value - count) < 1e-9 ? Ink.ground : Ink.text)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(abs(value - count) < 1e-9 ? Ink.text : Ink.raised, in: .capsule)
                            .buttonStyle(.plain)
                    }
                    Spacer(minLength: 4)
                    Menu {
                        Button("Units, Time and Nutrients…", systemImage: "slider.horizontal.3") {
                            // Saved first, so the panel opens on the new amount rather than writing the old back.
                            save()
                            more(model.current(entry) ?? entry)
                        }
                        Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                    } label: {
                        Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(Ink.text2)
                            .frame(width: 44, height: 32).contentShape(.rect)
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("today.amount.more")
                }
            }
        }
        .padding(14)
        .background(Color.cardBackground, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
        .onAppear {
            guard !opened else { return }
            opened = true
            draft = model.draft(for: .edit(entry))
            count = draft.amount.count ?? 1
        }
        // Closed by tapping another food or the field: what was set is saved all the same.
        .onDisappear(perform: save)
        .sensoryFeedback(.selection, trigger: count)
    }

    func step(_ label: String, _ symbol: String, _ by: Double, unit: PortionUnit) -> some View {
        Button {
            set(count + by, unit: unit)
        } label: {
            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(Ink.text)
                .frame(width: 48, height: 48).background(Ink.raised, in: .circle).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("today.amount.\(symbol)")
    }

    /// The ruler as the amount's scale: from nothing to two and a half times what was logged.
    func slider(_ unit: PortionUnit) -> some View {
        let most = max((draft.amount.count ?? 1) * 2.5, FoodUnits.step(for: unit) * 10)
        return GeometryReader { geometry in
            Ruler(value: count / most, height: 18)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                // Across sets the amount; up and down is the list's, to scroll.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6).onChanged { drag in
                        guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                        set(min(1, max(0, drag.location.x / max(1, geometry.size.width))) * most, unit: unit)
                    }
                )
                .onTapGesture { location in set(min(1, max(0, location.x / max(1, geometry.size.width))) * most, unit: unit) }
        }
        .frame(height: 34)
        .accessibilityElement()
        .accessibilityLabel("Amount")
        .accessibilityValue(FoodUnits.label(count: count, unit: unit))
        .accessibilityAdjustableAction { direction in
            set(count + (direction == .increment ? 1 : -1) * FoodUnits.step(for: unit), unit: unit)
        }
    }

    /// Half to double what was logged, as the amount panel offers them.
    func choices(_ unit: PortionUnit) -> [Double] {
        AmountChoices.quick(base: draft.amount.count ?? 1, unit: unit)
    }

    /// Snapped to the unit's step, never below one step.
    func set(_ value: Double, unit: PortionUnit) {
        let step = FoodUnits.step(for: unit)
        withAnimation(.snappy(duration: 0.2)) { count = max(step, (value / step).rounded() * step) }
    }

    func finish() {
        save()
        close()
    }

    /// Once, and only if the amount moved.
    func save() {
        guard opened, let unit = draft.amount.unit, abs(count - (draft.amount.count ?? count)) > 1e-9,
            let current = model.current(entry)
        else { return }
        let changed = model.rescaled(current, food: draft.food, unit: unit, count: count)
        model.update([changed], message: "Changed \(FoodLabel.short(entry.name)) to \(FoodUnits.label(count: count, unit: unit))")
        draft = model.draft(for: .edit(changed))
    }

    func delete() {
        opened = false
        close()
        model.delete(entries: [entry.id])
    }
}
