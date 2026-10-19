import MindEngine
import SwiftUI

/// A reading-test passage: read it once at your usual pace, then its questions follow without it.
/// The time it took is kept quietly; there's no clock on screen to hurry anyone.
struct PassageView: View {
    @Environment(AppModel.self) private var model
    let passage: Passage
    @State private var shown = Date()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Read it once, at your usual pace. The questions come after, without the passage.", systemImage: "text.book.closed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    // A comfortable measure, about 65 characters a line, whatever the window's width.
                    Text(passage.text)
                        .font(.passage)
                        .lineSpacing(LineSpacing.passage)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.disabled)
                    Text(credit).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
                .readableWidth(Platform.isMac ? 620 : 640)
            }
            BottomBar {
                Button(action: done) {
                    Text("Done reading").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .accessibilityIdentifier("passage.done")
                KeyLegend(bindings: keys, titles: [.submit: "Done reading"])
            }
        }
        .onAppear { shown = Date() }
        .sessionKeys(keys) { key in if key == .submit { done() } }
    }

    var keys: [SessionKeyBinding] { SessionKeys.bindings(step: .passage(passage), feedback: nil) }

    func done() {
        let seconds = Date().timeIntervalSince(shown)
        model.act { $0.respond(.passageRead(seconds: seconds), now: Date()) }
    }

    var credit: String {
        passage.author == "Mind Track" ? "Written for Mind Track" : "From \(passage.title), \(passage.author)"
    }
}
