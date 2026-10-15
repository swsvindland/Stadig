import SwiftUI
import ExerciseLibrary
import LiftEngine
import SystemCore

/// Every item in the session, to jump ahead, skip, or add a set.
struct ExerciseListView: View {
    @Environment(WatchModel.self) private var model
    let close: () -> Void

    var body: some View {
        List {
            if let live = model.live {
                ForEach(Array(live.items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        ItemDetailView(item: index, close: close)
                    } label: {
                        row(index, item)
                    }
                }
            }
        }
        .navigationTitle("Exercises")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark", action: close)
            }
        }
    }

    private func row(_ index: Int, _ item: LiveItem) -> some View {
        let current = model.position?.item == index
        let work = item.sets.filter { $0.prescription.kind != .warmup }
        let done = work.filter { !$0.isOpen }.count
        return HStack(spacing: 8) {
            Image(systemName: item.skipped ? "forward.fill" : item.isDone ? "checkmark.circle.fill" : current ? "arrow.right.circle.fill" : item.plan.block.symbol)
                .foregroundStyle(item.isDone && !item.skipped ? .green : current ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.catalog.resolve(item.exerciseID).name)
                    .font(.footnote.weight(current ? .semibold : .regular))
                    .lineLimit(2)
                Text(status(item, done: done, of: work.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func status(_ item: LiveItem, done: Int, of total: Int) -> LocalizedStringKey {
        if item.skipped { return "Skipped" }
        if let conditioning = item.plan.conditioning { return item.isDone ? "Done" : "\(conditioning.minutes) min" }
        return "\(done) of ^[\(total) set](inflect: true)"
    }
}

/// One item: its sets so far and what can be done with it.
struct ItemDetailView: View {
    @Environment(WatchModel.self) private var model
    let item: Int
    let close: () -> Void

    var body: some View {
        if let live = model.live, live.items.indices.contains(item) {
            let liveItem = live.items[item]
            let exercise = model.exercise(item)
            List {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name).font(.headline)
                        if let note = liveItem.plan.note {
                            Text(note).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Sets") {
                    ForEach(Array(liveItem.sets.enumerated()), id: \.element.id) { index, set in
                        setRow(set, index: index, in: liveItem, exercise: exercise)
                    }
                }
                Section {
                    if !liveItem.isDone && model.position?.item != item {
                        Button("Do This Now", systemImage: "arrow.right.circle") {
                            model.focus(item: item)
                            close()
                        }
                    }
                    if liveItem.plan.conditioning == nil {
                        Button("Add a Set", systemImage: "plus") { model.addSet(item: item) }
                    }
                    if let next = liveItem.nextSet, liveItem.sets.filter(\.isOpen).count > 1 {
                        Button("Skip Next Set", systemImage: "forward") { model.skipSet(item: item, set: next) }
                    }
                    if !liveItem.isDone {
                        Button("Skip Exercise", systemImage: "forward.end", role: .destructive) {
                            model.skip(item: item)
                            close()
                        }
                    }
                }
            }
            .navigationTitle(liveItem.plan.block.label)
        }
    }

    private func setRow(_ set: LiveSet, index: Int, in item: LiveItem, exercise: Exercise) -> some View {
        HStack(spacing: 6) {
            if let logged = set.logged {
                if let rating = logged.rating {
                    Image(systemName: rating.symbol).foregroundStyle(rating.tint)
                } else {
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                }
                Text(WatchFormat.logged(logged, exercise: exercise, unit: model.unit))
            } else if set.skipped {
                Image(systemName: "forward.fill").foregroundStyle(.secondary)
                Text("Skipped").foregroundStyle(.secondary)
            } else {
                Image(systemName: "circle").foregroundStyle(.secondary)
                Text(WatchFormat.prescription(set.prescription, exercise: exercise, unit: model.unit, plannedSeconds: item.plan.seconds))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(set, index: index, in: item, exercise: exercise))
    }

    private func accessibilityText(_ set: LiveSet, index: Int, in item: LiveItem, exercise: Exercise) -> String {
        let position = WatchFormat.setPosition(index, in: item.sets)
        if let logged = set.logged {
            return "\(position), done, \(WatchFormat.logged(logged, exercise: exercise, unit: model.unit))\(logged.rating.map { ", \($0.label)" } ?? "")"
        }
        if set.skipped { return "\(position), skipped" }
        return "\(position), \(WatchFormat.prescription(set.prescription, exercise: exercise, unit: model.unit, plannedSeconds: item.plan.seconds))"
    }
}
