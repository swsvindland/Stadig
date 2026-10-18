import SwiftUI
import MindEngine

// The v2 steps. Each subject builds its own screen out here; until then these do the minimum
// that lets a session move on: read and continue, write, pick one. Speaking is in LanguageSteps.swift.

/// A reading-test passage: read silently, then its questions follow. The time it took is kept.
struct PassageView: View {
    @Environment(AppModel.self) private var model
    let passage: Passage
    @State private var shown = Date()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Read this at your usual pace. Questions follow.").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text(passage.text).font(.body).lineSpacing(4).textSelection(.disabled)
                    Text("\(passage.title), \(passage.author)").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
                .readableWidth(640)
            }
            BottomBar {
                Button {
                    let seconds = Date().timeIntervalSince(shown)
                    model.act { $0.respond(.passageRead(seconds: seconds), now: Date()) }
                } label: {
                    Text("Done reading").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
            }
        }
        .onAppear { shown = Date() }
    }
}
