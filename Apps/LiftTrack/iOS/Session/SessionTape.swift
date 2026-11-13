import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

// The scoreboard's right third: the whole session as a tape.

/// The session as a vertical tape down the right third: each exercise with its sets as ticks (done
/// ones filled with their rating's dot, the one in front of you outlined), a marker at now, when each
/// one still to come should start, and at the foot the rest and when it should all be done.
struct SessionTape: View {
    @Environment(AppModel.self) private var model
    let live: LiveSession

    /// "6:48", without the AM or PM a glance across the room doesn't need.
    private static let time = Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute()
    /// Where the ticks start: past the times (52), the now-marker (14) and the gaps between (10 each).
    private static let trackX: CGFloat = 52 + 10 + 14 + 10

    var body: some View {
        TimelineView(.everyMinute) { context in
            let timeline = live.timeline(now: context.date)
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(Array(live.items.enumerated()), id: \.element.id) { index, item in
                                row(index, item, start: timeline.starts[item.id])
                                    .id(item.id)
                            }
                        }
                        // The tape itself: one track down the session, the sets ticked off it.
                        .background(alignment: .leading) {
                            Rectangle().fill(Ink.track).frame(width: 2).padding(.leading, Self.trackX - 2).padding(.vertical, -8)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 16)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear { scroll(proxy, animated: false) }
                    .onChange(of: live.current?.item) { scroll(proxy, animated: true) }
                }
                Rectangle().fill(Ink.hairline).frame(height: 1)
                footer(doneBy: timeline.doneBy)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let index = live.current?.item else { return }
        let id = live.items[max(0, index - 1)].id
        if animated {
            withAnimation { proxy.scrollTo(id, anchor: .top) }
        } else {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.eyebrow(live.plan)).font(.subheadline.weight(.semibold)).textCase(.uppercase).tracking(1.2)
                .foregroundStyle(Ink.text3)
            HStack(alignment: .firstTextBaseline) {
                Text(live.plan.title).font(.system(size: 34, weight: .heavy)).tracking(-1).foregroundStyle(Ink.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Text(live.startedAt, style: .timer)
                    .font(.system(size: 34, weight: .bold)).monospacedDigit().foregroundStyle(Ink.text2)
                    .accessibilityLabel("Session time")
            }
        }
        .padding(.bottom, 8)
    }

    /// "Block week 2", "Assessment", "Deload · Check-in".
    static func eyebrow(_ plan: SessionPlan) -> String {
        var parts: [String] = []
        if plan.assessment {
            parts.append("Assessment")
        } else if plan.deload {
            parts.append("Deload")
        } else if let week = plan.week {
            parts.append("Block week \(week + 1)")
        }
        if plan.checkIn { parts.append("Check-in") }
        return parts.isEmpty ? "Today" : parts.joined(separator: " · ")
    }

    private func row(_ index: Int, _ item: LiveItem, start: Date?) -> some View {
        let current = live.current?.item == index
        let resting = model.activeRest != nil
        let exercise = model.catalog.resolve(item.exerciseID)
        let warmups = item.sets.indices.filter { item.sets[$0].prescription.kind == .warmup }
        let work = item.sets.indices.filter { item.sets[$0].prescription.kind != .warmup }
        let detail = detail(index, item, exercise, current: current, resting: resting)
        return HStack(alignment: .top, spacing: 10) {
            Text(start.map { $0.formatted(Self.time) } ?? "")
                .font(.callout.weight(.medium)).monospacedDigit()
                .foregroundStyle(Ink.text3)
                .frame(width: 52, alignment: .trailing)
                .padding(.top, warmups.isEmpty ? 0 : CGFloat(warmups.count) * 8)
            Image(systemName: "arrowtriangle.right.fill")
                .font(.caption)
                .foregroundStyle(Ink.text)
                .opacity(current ? 1 : 0)
                .frame(width: 14)
                .padding(.top, CGFloat(warmups.count) * 8 + CGFloat(nowOffset(item, current: current, work: work)) * 26)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(warmups, id: \.self) { set in
                    UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2)
                        .fill(item.sets[set].isOpen ? Ink.track : Color.accentColor.opacity(0.55))
                        .frame(width: 26, height: 4)
                }
                VStack(spacing: 8) {
                    ForEach(work, id: \.self) { set in
                        Tick(set: item.sets[set], now: current && live.current?.set == set, resting: resting)
                    }
                }
            }
            .frame(width: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.title3.weight(current ? .bold : .semibold))
                    .foregroundStyle(item.isDone && !current ? Ink.text3 : current ? Ink.text : Ink.text2)
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.callout.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(current ? Color.accentColor : Ink.text3)
                        .lineLimit(2)
                }
            }
            .padding(.top, CGFloat(warmups.count) * 8 - 4)
            Spacer(minLength: 0)
        }
        .padding(.vertical, current ? 8 : 0)
        .background {
            // A wash rather than a fill, so the track still runs through the exercise in front of you.
            if current { Rectangle().fill(Ink.text.opacity(0.06)).padding(.horizontal, -24) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([exercise.name, detail, current ? "now" : nil].compactMap { $0 }.joined(separator: ", "))
    }

    /// How many work ticks down the now-marker sits: at the set in front of you.
    private func nowOffset(_ item: LiveItem, current: Bool, work: [Int]) -> Int {
        guard current, let set = live.current?.set else { return 0 }
        return work.firstIndex(of: set) ?? 0
    }

    /// What the tape says under an exercise: the set in front of you, "Rest, then set 2 of 3",
    /// "Done", or what it'll be.
    private func detail(_ index: Int, _ item: LiveItem, _ exercise: Exercise, current: Bool, resting: Bool) -> String? {
        let work = item.sets.filter { $0.prescription.kind != .warmup }
        if current, let set = live.current?.set {
            let prescription = item.sets[set].prescription
            let warmup = prescription.kind == .warmup
            let number =
                warmup
                ? item.sets[...set].filter { $0.prescription.kind == .warmup }.count
                : item.sets[...set].filter { $0.prescription.kind != .warmup }.count
            let of = warmup ? item.sets.filter { $0.prescription.kind == .warmup }.count : work.count
            let which = "\(warmup ? "warm-up" : "set") \(number) of \(of)"
            if resting { return "Rest, then \(which)" }
            let target = Format.set(prescription, exercise: exercise, unit: model.gym.unit)
            return "\(which.prefix(1).uppercased())\(which.dropFirst()) · \(target)"
        }
        if item.isDone { return item.skipped ? "Skipped" : "Done" }
        if let conditioning = item.plan.conditioning { return conditioning.summary }
        guard item.plan.isStrength, let first = work.first?.prescription else { return item.plan.block.label }
        // "3 × 8 · 60 kg", as a program lists it.
        var target = "\(work.count) × \(first.seconds.map(Format.duration) ?? "\(first.targetReps)")"
        if exercise.loadBasis != .none, let kg = first.loadKg, kg > 0 {
            target += " · \(Format.load(kg, unit: model.gym.unit, basis: exercise.loadBasis))"
        }
        return target
    }

    private func footer(doneBy: Date) -> some View {
        let rest = model.activeRest
        let after = live.current.map { live.items[$0.item].plan.rest.target } ?? 0
        let seconds = rest.map { Int($0.endsAt.timeIntervalSince($0.started).rounded()) } ?? after
        // Two columns of the same width, as the board's foot has them.
        return HStack(alignment: .bottom, spacing: 16) {
            Group {
                if seconds > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rest == nil ? "Rest after" : "Resting").font(.subheadline.weight(.semibold)).textCase(.uppercase).tracking(1.2)
                            .foregroundStyle(Ink.text3)
                        Text(Format.clock(seconds)).font(.system(size: 54, weight: .heavy)).tracking(-2.5).monospacedDigit()
                            .foregroundStyle(Ink.text2)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if !live.isComplete {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Done by").font(.subheadline.weight(.semibold)).textCase(.uppercase).tracking(1.2).foregroundStyle(Ink.text3)
                        Text(doneBy.formatted(Self.time)).font(.system(size: 54, weight: .heavy)).tracking(-2.5).monospacedDigit()
                            .foregroundStyle(Ink.text)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineLimit(1).minimumScaleFactor(0.6)
    }
}

/// A set on the tape: filled with its rating's dot once done, outlined while it's the one in front of
/// you (softly filled until its rest is over), the track's colour while it waits.
private struct Tick: View {
    let set: LiveSet
    let now: Bool
    let resting: Bool

    var body: some View {
        // Square against the track, rounded at its free end.
        let shape = UnevenRoundedRectangle(bottomTrailingRadius: 5, topTrailingRadius: 5, style: .continuous)
        ZStack(alignment: .trailing) {
            if set.logged != nil {
                shape.fill(Color.accentColor)
                if let rating = set.logged?.rating {
                    Circle().fill(rating.color).frame(width: 8, height: 8).padding(.trailing, 7)
                }
            } else if now {
                shape.fill(resting ? Color.clear : Color.accentColor.opacity(0.18))
                shape.strokeBorder(Color.accentColor, lineWidth: 2)
            } else {
                shape.fill(Ink.track).opacity(set.skipped ? 0.4 : 1)
            }
        }
        .frame(height: 18)
    }
}
