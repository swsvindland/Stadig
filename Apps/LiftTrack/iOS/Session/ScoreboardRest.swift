import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

// The scoreboard's rest: the countdown at the set's scale, Undo for the set just logged, what's next.

/// The rest over the left side: the set just logged with Undo, the countdown at the set's scale, the
/// draining ruler, the next set with its plates, and −15, +15 and Skip as big as the rating zones.
struct BoardRest: View {
    @Environment(AppModel.self) private var model
    @Environment(SetDraft.self) private var draft
    let live: LiveSession
    let rest: RestState

    var body: some View {
        let total = max(1, rest.endsAt.timeIntervalSince(rest.started))
        let restedItem = live.item(rest.itemID)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(restedItem.map { "Rest · exercise \($0 + 1) of \(live.items.count)" } ?? "Rest")
                        .font(.headline.weight(.semibold)).textCase(.uppercase).tracking(1.4)
                        .foregroundStyle(Ink.text3)
                    if let restedItem {
                        Text(model.catalog.resolve(live.items[restedItem].exerciseID).name)
                            .font(.system(size: 60, weight: .heavy)).tracking(-2.4)
                            .foregroundStyle(Ink.text)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                Spacer(minLength: 0)
                if let logged = model.justLogged(after: rest), logged.undoable { undo(logged) }
            }
            TimelineView(.periodic(from: rest.started, by: 1)) { context in
                let left = max(0, rest.endsAt.timeIntervalSince(context.date))
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        ViewThatFits(in: .horizontal) {
                            ForEach([220, 190, 160, 130] as [CGFloat], id: \.self) { size in
                                Text(Format.clock(Int(left.rounded(.up))))
                                    .font(.system(size: size, weight: .heavy)).tracking(-size * 0.05)
                                    .monospacedDigit()
                                    .foregroundStyle(Ink.text)
                                    .frame(height: size * 0.8)
                                    .fixedSize()
                            }
                        }
                        .accessibilityLabel("Rest left")
                        .accessibilityValue(Format.duration(Int(left.rounded(.up))))
                        Spacer(minLength: 12)
                        heartRate
                    }
                    Ruler(value: left / total, height: 52)
                    HStack {
                        Text("of \(Format.clock(Int(total.rounded())))")
                        Spacer()
                        if rest.plan.heartRateGuided, model.currentHeartRate != nil { Text("Ends early when your heart rate recovers") }
                    }
                    .font(.title3.weight(.medium)).foregroundStyle(Ink.text2)
                }
            }
            .padding(.top, 8)
            Spacer(minLength: 12)
            next
            Spacer(minLength: 12)
            if let filler = rest.filler {
                Text("Use the rest: \(model.catalog.resolve(filler).name)")
                    .font(.title3.weight(.semibold)).foregroundStyle(Ink.text2)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.bottom, 12)
            }
            HStack(spacing: 14) {
                BoardZone(title: "−15", detail: "seconds") { model.update { $0.extendRest(by: -15) } }
                    .accessibilityLabel("Fifteen seconds less")
                    .accessibilityIdentifier("scoreboard.less")
                BoardZone(title: "+15", detail: "seconds") { model.update { $0.extendRest(by: 15) } }
                    .accessibilityLabel("Fifteen seconds more")
                    .accessibilityIdentifier("scoreboard.more")
                BoardZone(title: "Skip", detail: "I'm ready") { model.update { $0.endRest() } }
                    .keyboardShortcut(.space, modifiers: [])
                    .accessibilityLabel("Skip rest")
                    .accessibilityIdentifier("scoreboard.skip")
            }
        }
        .padding(.horizontal, 44)
        .padding(.top, 28)
        .padding(.bottom, 32)
    }

    /// "● Set 3 · Easy" over Undo, in a card big enough to hit from the bar.
    private func undo(_ logged: JustLogged) -> some View {
        Button {
            draft.undo(model: model)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let rating = logged.rating { Circle().fill(rating.color).frame(width: 12, height: 12) }
                    Text([logged.name, logged.detail].compactMap { $0 }.joined(separator: " · "))
                        .font(.title3.weight(.semibold)).foregroundStyle(Ink.text2)
                }
                Text("Undo").font(.system(size: 30, weight: .bold)).foregroundStyle(Ink.text)
            }
            .padding(.horizontal, 22)
            .frame(minHeight: 96)
            .background(Ink.raised, in: .rect(cornerRadius: 24, style: .continuous))
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel("Undo \(logged.name.lowercased())")
        .accessibilityHint("\(logged.text). Takes it back to log again.")
        .accessibilityIdentifier("scoreboard.undo")
    }

    @ViewBuilder
    private var heartRate: some View {
        if let bpm = model.currentHeartRate {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 10) {
                    Image(systemName: "heart").font(.title.weight(.bold)).foregroundStyle(Ink.bad)
                    Text("\(Int(bpm))").font(.system(size: 64, weight: .heavy)).monospacedDigit().foregroundStyle(Ink.text)
                }
                Text("bpm").font(.title3).foregroundStyle(Ink.text2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heart rate \(Int(bpm))")
        }
    }

    /// The set after the rest: which, its target and the plates on the bar, and what the rating changed.
    @ViewBuilder
    private var next: some View {
        if let next = model.nextSet(after: rest) {
            VStack(alignment: .leading, spacing: 6) {
                Text(next.exercise.map { "\(next.label) · \($0)" } ?? next.label)
                    .font(.headline.weight(.semibold)).textCase(.uppercase).tracking(1.4)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                HStack(alignment: .center, spacing: 24) {
                    Text(next.target)
                        .font(.system(size: 80, weight: .heavy)).tracking(-3)
                        .monospacedDigit()
                        .foregroundStyle(Ink.text)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    if let plates = model.boardPlates(next: next) { BoardPlates(plates: plates, scale: 0.6) }
                }
                if let note = next.repOut ? (next.stopAtFormBreakdown ? "Stop when your form slips" : "As many as you can") : live.message {
                    Text(note).font(.title3.weight(.semibold)).foregroundStyle(Ink.text2).lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
