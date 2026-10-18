import SwiftUI
import MindEngine
import SystemCore

/// "Can't speak now" holds for a while, so a later part of the session doesn't ask again straight away.
@MainActor
enum SpeakingPause {
    static var until: Date?
    static var active: Bool { (until ?? .distantPast) > Date() }
}

/// Say something in the language, or write it. Saying listens with on-device speech recognition and
/// hands back what it heard; writing is typed. Afterwards (outside tests) it shows what was heard
/// or written beside the answer.
struct SpeakView: View {
    @Environment(AppModel.self) private var model
    let task: SpeakingTask
    let feedback: StudyRun.Feedback?
    @State private var recognizer = SpeechRecognizer.shared
    @State private var written = ""
    @State private var shown = Date()
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(task.instruction).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if task.kind == .test { Pill(text: "Test", symbol: "gauge.with.dots.needle.50percent") }
                    }
                    PromptView(prompt: task.prompt, revealed: feedback != nil)
                    if let hint = task.hint, feedback == nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Say this").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ScaffoldedText(text: hint, size: 24)
                        }
                        .card()
                    }
                    if let feedback {
                        SpokenFeedback(task: task, feedback: feedback)
                    } else if task.mode == .say {
                        listening
                    } else {
                        TextField("Write it here", text: $written, axis: .vertical)
                            .accessibilityIdentifier("speak.written")
                            .font(.title2)
                            .padding(14)
                            .background(.cardBackground, in: .rect(cornerRadius: 14))
                            .focused($typing)
                            .submitLabel(.done)
                            .onSubmit(check)
                            .environment(\.locale, Locale(identifier: task.language.pack.locale))
                        Text(task.language.pack.script == .kanaKanji ? "Kana or kanji, whichever you can." : "Accents help, but they won't count against you.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .readableWidth(640)
            }
            .scrollDismissesKeyboard(.never)
            BottomBar { bottom }
        }
        .sensoryFeedback(trigger: feedback?.correct) { _, correct in
            guard let correct, task.kind != .test else { return nil }
            return correct ? .success : .error
        }
        .onAppear {
            shown = Date()
            if task.mode == .say && SpeakingPause.active && feedback == nil {
                model.act { $0.respond(.skip, now: Date()) }
                return
            }
            if case .audio(let text, let language) = task.prompt, feedback == nil { model.speech.speak(text, language: language) }
            if task.mode == .write && feedback == nil { typing = true }
            #if DEBUG
            if LaunchOptions.current.has("-fakeSpeech"), task.mode == .say, feedback == nil {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    guard isCurrent else { return }
                    let said = task.answer
                    model.act { $0.respond(.spoken(transcript: said, seconds: 2), now: Date()) }
                }
            }
            #endif
        }
        .onDisappear { Task { await recognizer.cancel() } }
        .task(id: recognizer.isListening) {
            // Stops on its own after a pause once something's been said, or after fifteen seconds.
            // Only a step waiting for something said listens for it.
            guard task.mode == .say, feedback == nil, recognizer.isListening else { return }
            let started = Date()
            while !Task.isCancelled, recognizer.isListening {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard recognizer.isListening else { return }
                let quiet = Date().timeIntervalSince(recognizer.lastChange)
                if (!recognizer.heard.isEmpty && quiet > 1.6) || Date().timeIntervalSince(started) > 15 {
                    await submitSpeech()
                    return
                }
            }
        }
    }

    @ViewBuilder var listening: some View {
        VStack(spacing: 14) {
            Button {
                Task {
                    if recognizer.isListening { await submitSpeech() } else { await recognizer.start(task.language) }
                }
            } label: {
                Image(systemName: recognizer.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 38))
                    .frame(width: 96, height: 96)
                    .symbolEffect(.pulse, isActive: recognizer.isListening)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(recognizer.isBusy)
            .accessibilityLabel(recognizer.isListening ? "Stop listening" : "Start speaking")
            .accessibilityIdentifier("speak.mic")
            switch recognizer.status {
            case .idle: Text("Tap, then say it in \(task.language.pack.name)").font(.subheadline).foregroundStyle(.secondary)
            case .preparing(let message): ProgressView(message).font(.subheadline)
            case .listening:
                Text(recognizer.heard.isEmpty ? "Listening…" : recognizer.heard).font(.title3).multilineTextAlignment(.center)
                    .environment(\.locale, Locale(identifier: task.language.pack.locale))
            case .finishing: ProgressView()
            case .unavailable(let message): Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder var bottom: some View {
        if feedback != nil {
            Button {
                model.act { $0.next(now: Date()) }
            } label: {
                Text("Continue").font(.headline).frame(maxWidth: .infinity)
            }
            .primaryAction()
            .controlSize(.large)
            .accessibilityIdentifier("speak.continue")
        } else if task.mode == .say {
            HStack(spacing: 12) {
                Button {
                    Task { await recognizer.cancel() }
                    SpeakingPause.until = Date().addingTimeInterval(20 * 60)
                    model.act { $0.respond(.skip, now: Date()) }
                } label: {
                    Text("Can't speak now").frame(maxWidth: .infinity)
                }
                .secondaryAction()
                .controlSize(.large)
                .accessibilityIdentifier("speak.cantSpeak")
                if task.kind == .test {
                    Button {
                        Task { await recognizer.cancel() }
                        model.act { $0.respond(.spoken(transcript: "", seconds: 0), now: Date()) }
                    } label: {
                        Text("Don't know").frame(maxWidth: .infinity)
                    }
                    .secondaryAction()
                    .controlSize(.large)
                    .accessibilityIdentifier("speak.dontKnow")
                }
            }
        } else {
            HStack(spacing: 12) {
                Button {
                    model.act { $0.respond(.skip, now: Date()) }
                } label: {
                    Text(task.kind == .test ? "Don't know" : "Skip").frame(maxWidth: .infinity)
                }
                .secondaryAction()
                .controlSize(.large)
                .accessibilityIdentifier("speak.skip")
                Button(action: check) {
                    Text("Check").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .accessibilityIdentifier("speak.check")
                .disabled(written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    func check() {
        let text = written
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.act { $0.respond(.written(text: text, source: .typed), now: Date()) }
    }

    func submitSpeech() async {
        let said = await recognizer.finish()
        // Finishing takes a moment, and the step may have moved on meanwhile (skipped, or the
        // session ended): what was heard answers this task or nothing.
        guard isCurrent else { return }
        let seconds = Date().timeIntervalSince(shown)
        model.act { $0.respond(.spoken(transcript: said, seconds: seconds), now: Date()) }
    }

    /// This task is the step on screen, still waiting for its answer.
    var isCurrent: Bool {
        guard case .speak(let current)? = model.run?.step else { return false }
        return current.id == task.id && model.run?.feedback == nil
    }
}

/// How a spoken or written answer went: what was heard beside what counts, and its meaning.
private struct SpokenFeedback: View {
    let task: SpeakingTask
    let feedback: StudyRun.Feedback

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(feedback.correct ? "Understood" : "Not quite", systemImage: feedback.correct ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                .font(.headline)
                .foregroundStyle(feedback.correct ? .green : .orange)
            if let said = feedback.typed {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.mode == .say ? "Heard" : "You wrote").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(said.isEmpty ? "Nothing" : said).font(.title3)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                SpeakButton(text: task.answer, language: task.language, label: task.answer, font: .title3)
                if let meaning = task.meaning { Text(meaning).font(.subheadline).foregroundStyle(.secondary) }
            }
            if !feedback.correct, task.mode == .say {
                Text("Listen, then try it out loud once more for yourself. It doesn't need to be perfect to be understood.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

/// Text in the language with its fading scaffold: furigana over kanji, romaji or a stress guide
/// under the rest, on each item not yet mastered.
struct ScaffoldedText: View {
    let text: Scaffolded
    var size: CGFloat = 28
    var centred = false

    var body: some View {
        let above = text.segments.contains { $0.help != nil && $0.kind == .furigana }
        let below = text.segments.contains { $0.help != nil && $0.kind != .furigana }
        RubyFlow(spacing: 0, lineSpacing: 6, centred: centred) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                VStack(spacing: 0) {
                    if above { help(piece.kind == .furigana ? piece.help : nil) }
                    Text(piece.text).font(.system(size: size, weight: .medium))
                    if below { help(piece.kind != .furigana ? piece.help : nil) }
                }
            }
        }
        .environment(\.locale, Locale(identifier: text.language.pack.locale))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.text)
    }

    func help(_ text: String?) -> some View {
        Text(text ?? " ").font(.system(size: max(11, size * 0.42))).foregroundStyle(.secondary).fixedSize()
    }

    /// Plain runs split so they can wrap: Japanese by character, others by word.
    var pieces: [Scaffolded.Segment] {
        text.segments.flatMap { segment -> [Scaffolded.Segment] in
            guard segment.help == nil else { return [segment] }
            if text.language.pack.script == .kanaKanji { return segment.text.map { Scaffolded.Segment(text: String($0)) } }
            var out: [Scaffolded.Segment] = []
            var word = ""
            for character in segment.text {
                word.append(character)
                if character == " " {
                    out.append(Scaffolded.Segment(text: word))
                    word = ""
                }
            }
            if !word.isEmpty { out.append(Scaffolded.Segment(text: word)) }
            return out
        }
    }
}

/// Lays pieces of text out in lines, optionally centred, each piece the same shape so they line up.
struct RubyFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var centred: Bool

    func lines(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var lines: [[(index: Int, size: CGSize)]] = [[]]
        var used: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if used + size.width > width, !lines[lines.count - 1].isEmpty {
                lines.append([])
                used = 0
            }
            lines[lines.count - 1].append((index, size))
            used += size.width + spacing
        }
        return lines
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lines(subviews, width: width)
        let heights = lines.map { $0.map(\.size.height).max() ?? 0 }
        let widths = lines.map { $0.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(0, $0.count - 1)) }
        return CGSize(width: proposal.width ?? (widths.max() ?? 0),
                      height: heights.reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(subviews, width: bounds.width) {
            let width = line.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(0, line.count - 1))
            var x = centred ? bounds.minX + (bounds.width - width) / 2 : bounds.minX
            let height = line.map(\.size.height).max() ?? 0
            for item in line {
                subviews[item.index].place(at: CGPoint(x: x, y: y + height - item.size.height), proposal: .unspecified)
                x += item.size.width + spacing
            }
            y += height + lineSpacing
        }
    }
}

/// A sentence after it's been answered, or in a lesson: with its scaffold, a button to hear it,
/// and its English.
struct SentenceLine: View {
    @Environment(AppModel.self) private var model
    let sentence: Sentence
    let language: Language

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                if let run = model.run {
                    ScaffoldedText(text: run.scaffold(sentence, in: language), size: 20)
                } else {
                    Text(sentence.text).font(.title3)
                }
                Spacer(minLength: 0)
                Button {
                    model.speech.speak(sentence.text, language: language)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Play the sentence")
            }
            Text(sentence.english).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
