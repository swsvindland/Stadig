import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

extension SupplementForm {
    var symbol: String {
        switch self {
        case .capsule, .softgel, .tablet, .lozenge, .other: "pills.fill"
        case .gummy: "seal.fill"
        case .powder, .packet: "takeoutbag.and.cup.and.straw.fill"
        case .liquid, .drops: "drop.fill"
        }
    }
}

/// The day's doses on Today, by time of day: a tap marks one taken, "Take all" a time's worth.
/// Once everything's marked it folds to one line.
struct SupplementsSection: View {
    @Environment(AppModel.self) private var model
    let day: Day
    @State private var expanded = false
    @State private var editing: Supplement?

    var body: some View {
        let doses = model.doses(on: day)
        let extras = SupplementPlan.extras(on: day, logs: model.supplementLogs)
        if !doses.isEmpty || !extras.isEmpty {
            Section {
                if !doses.isEmpty, !doses.contains(where: \.open), !expanded {
                    Button {
                        withAnimation(.snappy) { expanded = true }
                    } label: {
                        summary(doses)
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .accessibilityIdentifier("supplements.summary")
                } else {
                    let times = DoseTime.allCases.filter { time in doses.contains { $0.dose.time == time } }
                    ForEach(times) { time in
                        let group = doses.filter { $0.dose.time == time }
                        TimeRow(time: time, minutes: model.settings.minutes(time), open: group.filter(\.open).count) {
                            model.take(
                                group.filter(\.open), on: day,
                                message: "Took \(group.filter(\.open).count) \(time.label.lowercased()) supplements")
                        }
                        ForEach(group) { dose in
                            DoseRow(dose: dose, day: day, edit: { editing = dose.supplement })
                        }
                    }
                }
                ForEach(extras) { log in
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.green).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.name).font(.subheadline)
                            Text("Extra · \(log.amountLabel) · \(Format.time(log.date))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { model.delete(doses: [log.id]) }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { model.delete(doses: [log.id]) }
                    }
                }
            } header: {
                HStack {
                    Text("Supplements")
                    Spacer()
                    Menu {
                        ForEach(model.activeSupplements) { supplement in
                            Button(supplement.name, systemImage: supplement.facts.form.symbol) { model.takeExtra(supplement) }
                        }
                    } label: {
                        Image(systemName: "plus.circle").font(.title3)
                    }
                    .accessibilityLabel("Take an extra dose")
                    .accessibilityIdentifier("supplements.takeExtra")
                    Button {
                        model.showSupplements = true
                    } label: {
                        Text("Edit").font(.subheadline)
                    }
                    .accessibilityIdentifier("supplements.edit")
                }
                .sheet(item: $editing) { supplement in
                    NavigationStack { SupplementEditor(supplement: supplement, isNew: false) }.macSheetSize(width: 520, height: 640)
                }
            }
        }
    }

    func summary(_ doses: [DueDose]) -> some View {
        let taken = doses.filter(\.taken).count
        let skipped = doses.count - taken
        return HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(skipped == 0 ? "All \(taken) taken" : "\(taken) taken, \(skipped) skipped").font(.subheadline.weight(.semibold))
                Text(Set(doses.map(\.supplement.name)).sorted().joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }
}

/// A time of day's heading inside the section, with "Take all" while two or more are open.
private struct TimeRow: View {
    let time: DoseTime
    let minutes: Int
    let open: Int
    let takeAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: time.symbol).font(.caption.weight(.semibold))
            Text(time.label).font(.caption.weight(.semibold))
            Spacer()
            if open >= 2 {
                Button("Take all", action: takeAll)
                    .accessibilityIdentifier("supplements.takeAll.\(time.rawValue)")
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
            }
        }
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden, edges: .bottom)
        .padding(.top, 2)
    }
}

/// One planned dose: a tap takes it (or takes it back); swipe to skip.
private struct DoseRow: View {
    @Environment(AppModel.self) private var model
    let dose: DueDose
    let day: Day
    let edit: () -> Void

    var body: some View {
        Button {
            if dose.taken { model.untake(dose) } else { model.take([dose], on: day) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: dose.taken ? "checkmark.circle.fill" : (dose.skipped ? "minus.circle" : "circle"))
                    .font(.title3)
                    .foregroundStyle(dose.taken ? Color.green : Color.secondary)
                    .frame(width: 24)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(dose.supplement.name).font(.subheadline).lineLimit(1)
                        .foregroundStyle(dose.open ? .primary : .secondary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityIdentifier("supplements.dose")
        .sensoryFeedback(.success, trigger: dose.taken) { _, taken in taken }
        .swipeActions(edge: .trailing) {
            if dose.skipped {
                Button("Unskip", systemImage: "arrow.uturn.backward") { model.untake(dose) }
            } else {
                Button("Skip", systemImage: "minus.circle") { model.skip(dose, on: day) }.tint(.orange)
            }
        }
        .contextMenu {
            if !dose.taken { Button("Taken", systemImage: "checkmark") { model.take([dose], on: day) } }
            if !dose.skipped { Button("Skip today", systemImage: "minus.circle") { model.skip(dose, on: day) } }
            Button("Edit \(dose.supplement.name)", systemImage: "pencil", action: edit)
        }
        .accessibilityLabel(
            "\(dose.supplement.name), \(dose.supplement.facts.amountLabel(dose.dose.count)), \(dose.taken ? "taken" : dose.skipped ? "skipped" : "not taken yet")"
        )
        .accessibilityHint(dose.taken ? "Marks it not taken" : "Marks it taken")
    }

    var detail: String {
        let amount = dose.supplement.facts.amountLabel(dose.dose.count)
        if let log = dose.log, log.taken { return "\(amount) · \(Format.time(log.date))" }
        if dose.skipped { return "\(amount) · skipped" }
        return amount
    }
}

/// The stack on the Plan tab: what's taken when, or a way to start one.
struct SupplementsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Supplements").font(.headline)
                Spacer()
                if !model.activeSupplements.isEmpty {
                    Text("\(model.activeSupplements.count) in your stack").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.activeSupplements.isEmpty {
                Text(
                    "Scan the bottle, say when you take it, and tick it off on Today. What you take counts toward your vitamins and minerals, and anything over a safe upper limit is flagged."
                )
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Add supplements") { model.showSupplements = true }.primaryAction()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.activeSupplements) { supplement in
                        VStack(alignment: .leading, spacing: 1) {
                            Label(supplement.name, systemImage: supplement.facts.form.symbol).font(.subheadline).lineLimit(1)
                            Text(supplement.scheduleLabel).font(.caption).foregroundStyle(.secondary).padding(.leading, 30)
                        }
                    }
                }
                Button("Edit supplements") { model.showSupplements = true }.secondaryAction()
            }
        }
        .card()
    }
}
