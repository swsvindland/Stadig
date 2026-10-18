import SwiftUI
import MindEngine

// The v2 steps. Each subject builds its own screen out here; until then these do the minimum
// that lets a session move on: say or type something, write, pick one. (Reading's passage is in
// ReadingTestViews.swift.)

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

/// Write something: a prompt, a rewrite, a practical task.
struct ComposeView: View {
    @Environment(AppModel.self) private var model
    let task: WritingTask
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(task.instruction).font(.title3.weight(.medium))
                    if let source = task.source {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(source).font(.body.italic())
                            if let credit = task.sourceCredit { Text(credit).font(.caption).foregroundStyle(.secondary) }
                        }
                        .card()
                    }
                    if let notes = task.notes {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your notes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(notes).font(.callout)
                        }
                        .card()
                    }
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(.cardBackground, in: .rect(cornerRadius: 14))
                    Text("\(text.split { $0.isWhitespace || $0.isNewline }.count) words · about \(task.minutes) minutes")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
                .readableWidth(640)
            }
            .scrollDismissesKeyboard(.interactively)
            BottomBar {
                Button {
                    let written = text
                    model.act { $0.respond(.written(text: written, source: .typed), now: Date()) }
                } label: {
                    Text("Done").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

/// Two pieces, unlabelled: which is stronger?
struct CompareView: View {
    @Environment(AppModel.self) private var model
    let pair: BlindPair

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Which is stronger?").font(.title.bold())
                Text(pair.prompt).font(.subheadline).foregroundStyle(.secondary)
                ForEach(Array([pair.first, pair.second].enumerated()), id: \.offset) { index, piece in
                    Button {
                        model.act { $0.respond(.picked(index), now: Date()) }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(index == 0 ? "A" : "B").font(.headline)
                            Text(piece.text).font(.body).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .readableWidth(640)
        }
    }
}
