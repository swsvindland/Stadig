import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

// The phone's session: one exercise at a time under a slim bar of the session's exercises, its sets
// in a card, and the dock at the bottom that logs the set in front of you or runs the rest.

extension View {
    /// The dock the logger and the rest sit in: a raised slab at the bottom of the screen, in thumb reach.
    func sessionDock() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(visionOS)
        .background(.regularMaterial, in: .rect(cornerRadius: 32, style: .continuous))
            #else
        .background(Ink.surface, in: .rect(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 1))
            #endif
    }
}

extension Format {
    /// "25 kg a side · 20 + 5", or nil when there's nothing to put on.
    static func plates(_ plates: [Double]?, unit: WeightUnit) -> String? {
        guard let plates, !plates.isEmpty else { return nil }
        let side = number(plates.reduce(0, +), digits: 2)
        let list = plates.map { number($0, digits: 2) }.joined(separator: " + ")
        // Past two plates the list no longer fits beside the set: the total says enough.
        return plates.count == 1 || plates.count > 2 ? "\(side) \(unit.symbol) a side" : "\(side) \(unit.symbol) a side · \(list)"
    }

    /// "70×7", the short form a row of warm-ups is written in.
    static func short(load kg: Double?, reps: Int, exercise: Exercise, unit: WeightUnit) -> String {
        guard let kg, exercise.loadBasis != .none, kg > 0 else { return "\(reps)" }
        return "\(number(unit.fromKilograms(kg), digits: 2))×\(reps)"
    }
}

extension AppModel {
    /// The same set the last time this exercise was done: the first set then for set 1, the second
    /// for set 2, or that session's last set when this one has more. Read from the end of the history,
    /// so it costs a session's worth of sets, not the whole history.
    func lastTime(_ exercise: Exercise, setNumber: Int) -> LoggedSet? {
        guard let history = analysis?.history[exercise.id] else { return nil }
        var sets: [LoggedSet] = []
        var day: Day?
        for set in history.reversed() where set.kind != .warmup {
            let setDay = Day(set.date)
            guard setDay < today else { continue }
            if let day, setDay != day { break }
            day = setDay
            sets.append(set)
        }
        let session = Array(sets.reversed())
        guard !session.isEmpty else { return nil }
        return session[min(max(0, setNumber - 1), session.count - 1)]
    }
}

/// Minimise, the session's name and clock, and its menu, over a slim ruler for each exercise.
struct SessionTopBar: View {
    @Environment(AppModel.self) private var model
    let live: LiveSession
    let menu: AnyView

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    model.showSession = false
                } label: {
                    CircleIcon(symbol: "chevron.down")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimize")
                .accessibilityIdentifier("session.minimize")
                Spacer()
                VStack(spacing: 2) {
                    Text(live.plan.title).font(.headline).foregroundStyle(Ink.text)
                    HStack(spacing: 4) {
                        Text(live.startedAt, style: .timer)
                        if let position = live.current?.item {
                            Text("· exercise \(position + 1) of \(live.items.count)")
                        }
                        if let bpm = model.currentHeartRate {
                            Text("·")
                            Image(systemName: "heart.fill").foregroundStyle(Ink.bad)
                            Text("\(Int(bpm))").accessibilityLabel("Heart rate \(Int(bpm))")
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Ink.text2)
                }
                Spacer()
                Menu {
                    menu
                } label: {
                    CircleIcon(symbol: "ellipsis")
                }
                .accessibilityLabel("Session options")
                .accessibilityIdentifier("session.options")
            }
            ExerciseStrip(live: live)
        }
    }
}

/// One slim ruler for each exercise, filled as its sets are done: where you are in the session.
struct ExerciseStrip: View {
    let live: LiveSession

    var body: some View {
        Group {
            if live.items.count <= 10 {
                HStack(spacing: 5) {
                    ForEach(live.items) { item in
                        Ruler.thin(Self.done(item), color: item.skipped ? Ink.text3 : .accentColor)
                    }
                }
            } else {
                Ruler.thin(live.progress)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session progress")
        .accessibilityValue("\(Int((live.progress * 100).rounded())) percent")
    }

    static func done(_ item: LiveItem) -> Double {
        if item.isDone { return 1 }
        guard !item.sets.isEmpty else { return item.conditioning != nil || item.heat != nil ? 1 : 0 }
        return Double(item.sets.filter { !$0.isOpen }.count) / Double(item.sets.count)
    }
}

/// The exercise in front of you: what it is and how to do it today, its sets, and what's next.
struct FocusedExercise: View {
    @Environment(AppModel.self) private var model
    let live: LiveSession
    let index: Int
    let swap: (Int) -> Void
    let edit: (Int) -> Void

    var body: some View {
        let item = live.items[index]
        let exercise = model.catalog.resolve(item.exerciseID)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow(item, exercise)).eyebrow(.accentColor)
                Text(exercise.name)
                    .font(.system(size: 30, weight: .bold)).tracking(-0.8)
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let replaced = item.plan.substitutedFor {
                    Text("Instead of \(model.catalog.resolve(replaced).name)").font(.caption).foregroundStyle(Ink.text2)
                }
                if let advice = advice(item) {
                    Text(advice).font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                }
                if !exercise.cue.isEmpty {
                    Label(exercise.cue, systemImage: "lightbulb").font(.caption).foregroundStyle(Ink.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            if let conditioning = item.plan.conditioning {
                VStack(alignment: .leading, spacing: 6) {
                    Text(conditioning.summary).font(.body.weight(.semibold).monospacedDigit())
                    if let log = item.conditioning {
                        Text("Done: \(log.minutes) min\(log.averageHeartRate.map { " · avg \(Int($0)) bpm" } ?? "")").font(.subheadline)
                            .foregroundStyle(Ink.text2)
                    }
                }
                .card(padding: 14, radius: 18)
            } else if !item.sets.isEmpty {
                SetListCard(item: item, exercise: exercise, current: live.current?.item == index ? live.current?.set : nil, edit: edit)
            }
            if let next = nextIndex {
                nextLine(next)
            }
            rest
        }
    }

    /// "Main lift · Chest", "Superset · Back".
    private func eyebrow(_ item: LiveItem, _ exercise: Exercise) -> String {
        var parts = [item.plan.supersetGroup != nil ? "Superset" : item.plan.block.label]
        if let muscle = exercise.primaryMuscles.first, exercise.kind == .strength { parts.append(muscle.label) }
        return parts.joined(separator: " · ")
    }

    private func advice(_ item: LiveItem) -> String? {
        let lines = [item.plan.reason, item.plan.isStrength ? item.plan.note : nil].compactMap { $0 }.filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    /// The first exercise after this one that isn't done.
    private var nextIndex: Int? {
        live.items.indices.first { $0 > index && !live.items[$0].isDone }
            ?? live.items.indices.first { $0 != index && !live.items[$0].isDone }
    }

    private func nextLine(_ next: Int) -> some View {
        let item = live.items[next]
        let exercise = model.catalog.resolve(item.exerciseID)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next").eyebrow()
                Text(exercise.name).font(.body.weight(.semibold)).foregroundStyle(Ink.text)
            }
            Spacer()
            Text(summary(item, exercise)).font(.caption.monospacedDigit()).foregroundStyle(Ink.text2)
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    /// Every other exercise, with what can be done to it: do it now, swap it, add a set, skip it.
    private var rest: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The whole session").eyebrow().padding(.horizontal, 4).padding(.top, 14)
            VStack(spacing: 0) {
                ForEach(Array(live.items.enumerated()), id: \.element.id) { position, item in
                    if position > 0 { Rectangle().fill(Ink.hairline).frame(height: 1) }
                    OtherExerciseRow(
                        live: live, index: position, isCurrent: live.current?.item == position, swap: { swap(position) })
                }
            }
            .padding(.horizontal, 14)
            .background(.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
        }
    }

    private func summary(_ item: LiveItem, _ exercise: Exercise) -> String {
        if let conditioning = item.plan.conditioning { return conditioning.summary }
        let work = item.sets.filter { $0.prescription.kind != .warmup }
        guard let first = work.first else { return item.plan.block.label }
        if item.plan.isStrength, !exercise.timed {
            guard let kg = first.prescription.loadKg, exercise.loadBasis != .none else { return "\(work.count) × \(first.prescription.targetReps)" }
            return "\(work.count) × \(first.prescription.targetReps) · \(Format.load(kg, unit: model.gym.unit, basis: exercise.loadBasis))"
        }
        return "\(work.count) × \(Format.set(first.prescription, exercise: exercise, unit: model.gym.unit))"
    }
}

/// A row of the whole session: its name, how far along, and its menu.
private struct OtherExerciseRow: View {
    @Environment(AppModel.self) private var model
    let live: LiveSession
    let index: Int
    let isCurrent: Bool
    let swap: () -> Void

    var body: some View {
        let item = live.items[index]
        let exercise = model.catalog.resolve(item.exerciseID)
        let work = item.sets.filter { $0.prescription.kind != .warmup }
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.subheadline.weight(isCurrent ? .semibold : .regular)).foregroundStyle(Ink.text).lineLimit(1)
                Text(
                    item.skipped
                        ? "Skipped"
                        : item.plan.conditioning?.summary
                            ?? (work.isEmpty
                                ? item.plan.block.label : "\(work.filter { !$0.isOpen }.count) of \(work.count) \(work.count == 1 ? "set" : "sets")")
                )
                .font(.caption.monospacedDigit()).foregroundStyle(Ink.text2)
            }
            Spacer()
            if isCurrent {
                Text("Now").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
            } else if item.isDone, !item.skipped {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Ink.good).accessibilityLabel("Done")
            }
            Menu {
                if !item.isDone && !isCurrent {
                    Button("Do this now", systemImage: "arrow.up.to.line") { model.update { $0.doNext(item: index) } }
                }
                if item.plan.isStrength {
                    Button("Swap exercise", systemImage: "arrow.triangle.2.circlepath", action: swap)
                        .accessibilityIdentifier("session.swap")
                }
                if item.takesMoreSets {
                    Button("Add a set", systemImage: "plus") { model.update { $0.addSet(item: index) } }
                }
                if !item.isDone { Button("Skip", systemImage: "forward") { model.update { $0.skip(item: index) } } }
            } label: {
                Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(Ink.text2).frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("\(exercise.name) options")
            .accessibilityIdentifier("session.itemOptions")
        }
        .frame(minHeight: 52)
        .opacity(item.isDone && !isCurrent ? 0.6 : 1)
    }
}

/// The current exercise's sets: the warm-ups folded into one line, the done ones quiet with their
/// rating, the one in front of you marked Now.
struct SetListCard: View {
    @Environment(AppModel.self) private var model
    let item: LiveItem
    let exercise: Exercise
    /// The set in front of you, when this is the current exercise.
    let current: Int?
    let edit: (Int) -> Void

    var body: some View {
        let warmups = item.sets.indices.filter { item.sets[$0].prescription.kind == .warmup }
        let foldWarmups = warmups.count > 1 && !warmups.contains { $0 == current }
        VStack(spacing: 0) {
            if foldWarmups {
                warmupLine(warmups)
            }
            ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, set in
                if !(foldWarmups && set.prescription.kind == .warmup) {
                    if index > 0 || foldWarmups { Rectangle().fill(Ink.hairline).frame(height: 1) }
                    row(index, set)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func warmupLine(_ indices: [Int]) -> some View {
        let done = indices.allSatisfy { !item.sets[$0].isOpen }
        let line = indices.map { index in
            let set = item.sets[index]
            return Format.short(
                load: set.logged?.loadKg ?? set.prescription.loadKg, reps: set.logged?.reps ?? set.prescription.targetReps, exercise: exercise,
                unit: model.gym.unit)
        }
        return HStack(spacing: 12) {
            SetNumber(text: "W", state: done ? .done : .pending)
            Text("Warm-up · \(line.joined(separator: " · "))").font(.subheadline.monospacedDigit()).foregroundStyle(Ink.text2).lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if done { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Ink.good).accessibilityLabel("Done") }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func row(_ index: Int, _ set: LiveSet) -> some View {
        if let logged = set.logged, item.plan.isStrength {
            // A logged set opens for a correction: the wrong weight, a rating tapped too fast. One
            // logged before a swap reads as the exercise it was done on.
            let doneOn = model.catalog.resolve(logged.exerciseID)
            Button {
                edit(index)
            } label: {
                line(index, set, exercise: doneOn)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityHint("Edit this set")
            .accessibilityIdentifier("session.loggedSet")
        } else {
            line(index, set, exercise: exercise)
        }
    }

    private func line(_ index: Int, _ set: LiveSet, exercise: Exercise) -> some View {
        let isNow = current == index
        let unit = model.gym.unit
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                SetNumber(text: number(of: index), state: set.logged != nil || set.skipped ? .done : (isNow ? .now : .pending))
                if let logged = set.logged {
                    SetValue(
                        load: logged.loadKg, reps: logged.reps, seconds: logged.seconds, plus: false, exercise: exercise, unit: unit, quiet: true)
                    Spacer(minLength: 4)
                    if let rating = logged.rating {
                        HStack(spacing: 6) {
                            RatingMark(rating: rating)
                            Text(rating.label).font(.caption).foregroundStyle(Ink.text2)
                        }
                    }
                } else if set.skipped {
                    Text("Skipped").font(.subheadline).foregroundStyle(Ink.text3)
                    Spacer()
                } else {
                    SetValue(
                        load: set.prescription.loadKg, reps: set.prescription.targetReps, seconds: set.prescription.seconds,
                        plus: set.prescription.kind == .repOut, exercise: exercise, unit: unit, quiet: !isNow)
                    Spacer(minLength: 4)
                    if isNow {
                        Chip(text: "Now", accent: true)
                    } else {
                        switch set.prescription.kind {
                        case .repOut: Chip(text: set.prescription.stopAtFormBreakdown ? "To form breakdown" : "As many as you can")
                        case .findingWeight: Chip(text: "Find weight")
                        case .deload: Chip(text: "Easy")
                        default: EmptyView()
                        }
                    }
                }
            }
            // During a rest the dock says it.
            if isNow, model.activeRest == nil, let note = set.note {
                Text(note).font(.caption).foregroundStyle(.tint).padding(.leading, 42)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// "W1", "W2" for warm-ups, then 1, 2, 3 for work.
    private func number(of index: Int) -> String {
        let set = item.sets[index]
        if set.prescription.kind == .warmup {
            return "W\(item.sets[...index].filter { $0.prescription.kind == .warmup }.count)"
        }
        return "\(item.sets[...index].filter { $0.prescription.kind != .warmup }.count)"
    }
}

/// A set's number in its circle: filled with the accent for the one in front of you, an outline once done.
struct SetNumber: View {
    enum State { case pending, now, done }
    let text: String
    let state: State

    var body: some View {
        Text(text)
            .font(.footnote.weight(.bold).monospacedDigit())
            .minimumScaleFactor(0.7)
            .foregroundStyle(state == .now ? Ink.onAccent : (state == .done ? Ink.text3 : Ink.text2))
            .frame(width: 30, height: 30)
            .background {
                switch state {
                case .now: Circle().fill(Color.accentColor)
                case .done: Circle().strokeBorder(Ink.hairline, lineWidth: 1.5)
                case .pending: Circle().fill(Ink.raised)
                }
            }
            .accessibilityHidden(true)
    }
}

/// "70 kg × 7" with the number large and the unit small; "45 s" for a timed set.
struct SetValue: View {
    let load: Double?
    let reps: Int
    let seconds: Int?
    let plus: Bool
    let exercise: Exercise
    let unit: WeightUnit
    let quiet: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let seconds, exercise.timed || exercise.kind != .strength {
                big(Format.duration(seconds))
            } else if exercise.loadBasis == .none || load == nil {
                big("\(reps)\(plus ? "+" : "")")
                small(" reps")
            } else {
                let parts = Format.load(load, unit: unit, basis: exercise.loadBasis).split(separator: " ", maxSplits: 1).map(String.init)
                big(parts.first ?? "")
                if parts.count > 1 { small(" \(parts[1])") }
                big(" × \(reps)\(plus ? "+" : "")")
            }
        }
        .monospacedDigit()
        .foregroundStyle(quiet ? Ink.text2 : Ink.text)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }

    private func big(_ text: String) -> some View { Text(text).font(.system(size: 20, weight: .bold)) }
    private func small(_ text: String) -> some View { Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.text2) }
}

/// A small capsule: "Now", "As many as you can".
struct Chip: View {
    let text: String
    var accent = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent ? Color.accentColor : Ink.text2)
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(accent ? Color.accentColor.opacity(0.16) : Ink.raised, in: .capsule)
            .lineLimit(1)
    }
}
