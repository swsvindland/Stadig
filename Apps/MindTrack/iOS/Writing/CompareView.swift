import SwiftUI
import MindEngine
import SystemCore

/// Two pieces, unlabelled and in random order: which is stronger? The AI judges the same pair
/// blind while the person reads, and its pick is kept back until theirs is in. Picking the newer
/// piece, time after time, is the measure of getting better.
struct CompareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let pair: BlindPair

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Which is stronger?").font(.title.bold())
                    Text("\(pair.prompt) Both are yours, written at least five weeks apart. Neither is labelled, and the order is random. Judge the writing, not which you remember.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    let layout = sizeClass == .regular ? AnyLayout(HStackLayout(alignment: .top, spacing: 14)) : AnyLayout(VStackLayout(spacing: 14))
                    layout {
                        card("A", pair.first)
                        card("B", pair.second)
                    }
                    Label("Apple Intelligence reads the same two pieces blind, as a second opinion.", systemImage: "eye.slash")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
                .readableWidth(sizeClass == .regular ? 1000 : 680)
            }
            BottomBar {
                HStack(spacing: 12) {
                    ForEach([0, 1], id: \.self) { index in
                        Button {
                            pick(index)
                        } label: {
                            Text("\(index == 0 ? "A" : "B") is stronger").font(.headline).frame(maxWidth: .infinity)
                        }
                        .primaryAction()
                        .controlSize(.large)
                        .accessibilityIdentifier("compare.pick.\(index)")
                    }
                }
            }
        }
        .task(id: pair.id) { WritingAssistant.shared.requestOpinion(on: pair, model: model) }
        #if DEBUG
        .task {
            if LaunchOptions.current.has("-autoPick") { pick(pair.first.id == pair.newer.id ? 0 : 1) }
        }
        #endif
    }

    func card(_ letter: String, _ piece: WritingPiece) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(letter).font(.title2.bold()).foregroundStyle(Domain.writing.color)
            Text(piece.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(4)
            Text(piece.text).font(.body).lineSpacing(3)
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Piece \(letter)")
    }

    func pick(_ index: Int) {
        let assistant = WritingAssistant.shared
        model.act { $0.respond(.picked(index), now: Date()) }
        // The AI may already have answered: its pick goes on now the person's is in.
        if case .picked(let newer?)? = assistant.opinions[pair.id] { assistant.record(newer, pair: pair, model: model) }
    }
}
