import SwiftUI
import MindEngine

// The v2 steps. Each subject builds its own screen out here; until then these do the minimum
// that lets a session move on: read and continue, say or type something, write, pick one.

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

/// Say something in the language. Until speech recognition is wired in, typing what you'd say
/// stands in for it.
struct SpeakView: View {
    @Environment(AppModel.self) private var model
    let task: SpeakingTask
    @State private var said = ""
    @State private var shown = Date()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(task.instruction).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    PromptView(prompt: task.prompt)
                    TextField("What you'd say", text: $said, axis: .vertical)
                        .font(.title3)
                        .padding(14)
                        .background(.cardBackground, in: .rect(cornerRadius: 14))
                }
                .padding(20)
                .readableWidth(640)
            }
            BottomBar {
                HStack(spacing: 12) {
                    Button {
                        model.act { $0.respond(.skip, now: Date()) }
                    } label: {
                        Text("Can't speak now").frame(maxWidth: .infinity)
                    }
                    .secondaryAction()
                    .controlSize(.large)
                    Button {
                        let seconds = Date().timeIntervalSince(shown)
                        let text = said
                        model.act { $0.respond(.spoken(transcript: text, seconds: seconds), now: Date()) }
                    } label: {
                        Text("Check").font(.headline).frame(maxWidth: .infinity)
                    }
                    .primaryAction()
                    .controlSize(.large)
                    .disabled(said.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            shown = Date()
            if case .audio(let text, let language) = task.prompt { model.speech.speak(text, language: language) }
        }
    }
}
