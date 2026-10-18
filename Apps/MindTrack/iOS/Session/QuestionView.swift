import SwiftUI
import MindEngine

/// Something new, shown before it's asked.
struct LessonView: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Pill(text: "New", symbol: "sparkles", color: .accentColor)
                    content
                }
                .padding(20)
                .readableWidth(640)
            }
            BottomBar {
                Button {
                    model.act { $0.next(now: Date()) }
                } label: {
                    Text(continueLabel).font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
            }
        }
        .onAppear(perform: speakIfLanguage)
    }

    var continueLabel: String {
        switch lesson {
        case .topic, .skill: "Start practising"
        default: "Got it"
        }
    }

    func speakIfLanguage() {
        switch lesson {
        case .word(let word, _, _): model.speech.speak(word.reading, language: word.language)
        case .kana(let kana): model.speech.speak(kana.kana, language: .japanese)
        default: break
        }
    }

    @ViewBuilder var content: some View {
        switch lesson {
        case .word(let word, let kanji, let example):
            WordCard(word: word, kanji: kanji)
            if let example {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In a sentence").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    SpeakButton(text: example.text, language: word.language, label: example.text, font: .title3)
                    Text(example.english).font(.subheadline).foregroundStyle(.secondary)
                }
                .card()
            }
        case .kana(let kana):
            VStack(spacing: 8) {
                Text(kana.kana).font(.system(size: 120, weight: .medium))
                Text(kana.romaji).font(.title.weight(.semibold))
                Text(kana.script.label).font(.subheadline).foregroundStyle(.secondary)
                SpeakButton(text: kana.kana, language: .japanese, label: "Hear it", font: .headline)
            }
            .frame(maxWidth: .infinity)
            .card(padding: 28)
        case .topic(let info, let example):
            Text(info.title).font(.title.bold())
            MathText(source: info.lesson, size: 18)
            VStack(alignment: .leading, spacing: 10) {
                Text("Worked example").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let figure = example.figure { DataFigureView(figure: figure) }
                MathText(source: example.prompt, size: 18, weight: .medium)
                Divider()
                ForEach(Array(example.steps.enumerated()), id: \.offset) { _, step in MathText(source: step, size: 17) }
                switch example.answer {
                case .choice(let i): MathText(source: "Answer: " + example.choices[i], size: 17, weight: .semibold)
                case .number(let value, let tolerance):
                    MathText(source: "Answer: $\(tolerance > 0 ? String(format: "%.2f", value.double) : value.tex)$", size: 17, weight: .semibold)
                }
            }
            .card()
        case .skill(let skill):
            Text(skill.title).font(.title.bold())
            Text(skill.lesson).font(.body)
            VStack(alignment: .leading, spacing: 6) {
                Text("For example").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(skill.example).font(.body.italic())
            }
            .card()
        }
    }
}

/// A word with its reading, meanings and, for Japanese, its kanji.
struct WordCard: View {
    @Environment(AppModel.self) private var model
    let word: Word
    let kanji: [Kanji]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 4) {
                if word.hasKanji { Text(word.kana).font(.title3).foregroundStyle(.secondary) }
                Text(word.text).font(.system(size: 56, weight: .medium)).minimumScaleFactor(0.5).lineLimit(1)
                Text(word.meaning).font(.title2.weight(.semibold))
                SpeakButton(text: word.reading, language: word.language, label: "Hear it", font: .subheadline)
            }
            .frame(maxWidth: .infinity)
            if word.meanings != word.meaning {
                Text(word.meanings).font(.subheadline).foregroundStyle(.secondary)
            }
            if !kanji.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(kanji, id: \.literal) { k in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(k.literal).font(.title)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(k.meanings).font(.subheadline.weight(.medium))
                                Text([k.onyomi, k.kunyomi].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.insetBackground, in: .rect(cornerRadius: 14))
            }
        }
        .card(padding: 20)
    }
}

struct SpeakButton: View {
    @Environment(AppModel.self) private var model
    let text: String
    let language: Language
    let label: String
    var font: Font = .body

    var body: some View {
        Button {
            model.speech.speak(text, language: language)
        } label: {
            Label(label, systemImage: "speaker.wave.2.fill").font(font)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Play \(label == text ? "the sentence" : label.lowercased())")
    }
}

/// One question: the prompt, the answers, and after answering, what was right and why.
struct QuestionView: View {
    @Environment(AppModel.self) private var model
    let question: Question
    let feedback: StudyRun.Feedback?
    @State private var typed = ""
    @State private var played = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(question.instruction).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if question.kind == .test { Pill(text: "Test", symbol: "gauge.with.dots.needle.50percent") }
                        if question.kind == .probe { Pill(text: "Quick check", symbol: "bolt") }
                        if question.timed && question.kind != .test { Pill(text: "Timed", symbol: "stopwatch") }
                    }
                    prompt
                    if let figure = question.figure { DataFigureView(figure: figure) }
                    answers
                    if let feedback { FeedbackPanel(question: question, feedback: feedback) }
                }
                .padding(20)
                .readableWidth(640)
            }
            .scrollDismissesKeyboard(.never)
            BottomBar { bottom }
        }
        .sensoryFeedback(trigger: feedback?.correct) { _, correct in
            guard let correct, question.kind != .test else { return nil }
            return correct ? .success : .error
        }
        .onAppear {
            if case .audio(let text, let language) = question.prompt { model.speech.speak(text, language: language) }
            if case .number = question.answer { typing = true }
        }
        .task(id: feedback) {
            // Tests move straight on: they measure, they don't teach. So does a timed problem
            // answered right and quickly; a slow one stays to show the quicker way.
            if let feedback, question.kind == .test || (question.timed && feedback.correct && question.fluent(model.run?.answered.last?.seconds)) {
                try? await Task.sleep(for: .milliseconds(question.kind == .test ? 450 : 700))
                model.act { $0.next(now: Date()) }
            }
        }
    }

    var prompt: some View { PromptView(prompt: question.prompt, revealed: feedback != nil) }

    @ViewBuilder var answers: some View {
        switch question.answer {
        case .choice(let right):
            VStack(spacing: 10) {
                ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                    ChoiceButton(text: choice, style: question.choiceStyle, state: state(index, right: right)) {
                        model.act { $0.choose(index, now: Date()) }
                    }
                    .disabled(feedback != nil)
                }
            }
        case .number(_, let tolerance):
            VStack(alignment: .leading, spacing: 8) {
                TextField("Your answer", text: $typed)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.title2.monospacedDigit())
                    .padding(14)
                    .background(.cardBackground, in: .rect(cornerRadius: 14))
                    .focused($typing)
                    .disabled(feedback != nil)
                    .submitLabel(.done)
                    .onSubmit(check)
                Text(tolerance > 0 ? "A decimal, rounded as asked" : "A whole number, a fraction like 3/4, or a decimal")
                    .font(.caption).foregroundStyle(.secondary)
                if let feedback, !feedback.correct {
                    MathText(source: "The answer is $\(question.shownAnswer)$", size: 18, weight: .semibold)
                }
            }
        }
    }

    func state(_ index: Int, right: Int) -> ChoiceButton.State {
        guard let feedback else { return .idle }
        if index == right { return .right }
        if index == feedback.chosen { return .wrong }
        return .dimmed
    }

    func check() {
        guard !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let text = typed
        model.act { $0.type(text, now: Date()) }
    }

    @ViewBuilder var bottom: some View {
        if feedback != nil {
            if question.kind != .test {
                Button {
                    model.act { $0.next(now: Date()) }
                } label: {
                    Text("Continue").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
            }
        } else {
            HStack(spacing: 12) {
                if question.allowsDontKnow {
                    Button {
                        model.act { $0.dontKnow(now: Date()) }
                    } label: {
                        Text(question.test == .mathsPlacement ? "Haven't learned this" : "Don't know").frame(maxWidth: .infinity)
                    }
                    .secondaryAction()
                    .controlSize(.large)
                }
                if case .number = question.answer {
                    Button(action: check) {
                        Text("Check").font(.headline).frame(maxWidth: .infinity)
                    }
                    .primaryAction()
                    .controlSize(.large)
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// What a question or task shows: text, the language (heard or seen), or maths.
struct PromptView: View {
    @Environment(AppModel.self) private var model
    let prompt: Prompt
    /// Audio shows its text once answered.
    var revealed = false

    var body: some View {
        switch prompt {
        case .text(let text):
            Text(text).font(.title3.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        case .foreign(let text, let language, let reading):
            VStack(spacing: 4) {
                if let reading { Text(reading).font(.title3).foregroundStyle(.secondary) }
                Text(text).font(.system(size: text.count > 12 ? 32 : text.count > 6 ? 40 : 60, weight: .medium)).minimumScaleFactor(0.4)
                    .multilineTextAlignment(.center)
                    .environment(\.locale, Locale(identifier: language.pack.locale))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        case .audio(let text, let language):
            VStack(spacing: 12) {
                Button {
                    model.speech.speak(text, language: language)
                } label: {
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 40)).frame(width: 96, height: 96)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Play again")
                Button("Slower") { model.speech.speak(text, language: language, slow: true) }.font(.subheadline)
                if revealed { Text(text).font(.title2).multilineTextAlignment(.center) }
            }
            .frame(maxWidth: .infinity)
        case .math(let text):
            MathText(source: text, size: 21, weight: .medium)
        }
    }
}

struct ChoiceButton: View {
    enum State { case idle, right, wrong, dimmed }

    let text: String
    let style: ChoiceStyle
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    switch style {
                    case .math: MathText(source: text, size: 19)
                    case .foreign: Text(text).font(.title2)
                    case .text: Text(text).font(.body).multilineTextAlignment(.leading)
                    case .picture:
                        Image(systemName: text).font(.system(size: 34)).frame(maxWidth: .infinity, minHeight: 56)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if state == .right { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                if state == .wrong { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 54)
            .background(background, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(border, lineWidth: state == .idle ? 0 : 2))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(state == .dimmed ? 0.5 : 1)
        .accessibilityLabel(style == .math ? MathSource.spoken(text) : style == .picture ? text.replacingOccurrences(of: ".", with: " ") : text)
        .accessibilityValue(state == .right ? "Right answer" : state == .wrong ? "Your answer, wrong" : "")
    }

    var background: Color {
        switch state {
        case .right: .green.opacity(0.14)
        case .wrong: .red.opacity(0.12)
        default: .cardBackground
        }
    }

    var border: Color { state == .right ? .green : state == .wrong ? .red : .clear }
}

/// Right or not, then what's worth knowing either way.
struct FeedbackPanel: View {
    @Environment(AppModel.self) private var model
    let question: Question
    let feedback: StudyRun.Feedback

    /// A timed problem says how long it took against its target.
    var verdict: String {
        guard feedback.correct else { return feedback.skipped ? "Here it is" : "Not quite" }
        guard question.timed, let seconds = model.run?.answered.last?.seconds else { return "Right" }
        let taken = Format.seconds(seconds)
        return question.fluent(seconds) ? "Right · \(taken)" : "Right, in \(taken): aim for \(Format.seconds(question.expectedSeconds))"
    }

    var body: some View {
        if question.kind == .test {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label(verdict, systemImage: feedback.correct ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                    .font(.headline)
                    .foregroundStyle(feedback.correct ? .green : .orange)
                switch question.reveal {
                case .word(let word, let kanji):
                    WordCard(word: word, kanji: kanji)
                case .sentence(let sentence, let language):
                    VStack(alignment: .leading, spacing: 6) {
                        SpeakButton(text: sentence.text, language: language, label: sentence.text, font: .title3)
                        Text(sentence.english).font(.subheadline).foregroundStyle(.secondary)
                    }
                case .steps(let steps):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { _, step in MathText(source: step, size: 17) }
                    }
                case .note(let note):
                    Text(note).font(.subheadline)
                case nil:
                    EmptyView()
                }
                if !feedback.correct && question.kind == .review {
                    Text("It comes round again in a few questions, and tomorrow.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }
}

/// The action bar along the bottom of a step.
struct BottomBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .readableWidth(640)
            .background(.bar)
    }
}
