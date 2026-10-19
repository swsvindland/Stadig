import Foundation

/// What a key does in a session, at a desk: the Mac, or an iPad or Vision Pro with a keyboard.
public enum SessionKey: Hashable, Sendable {
    /// Picks the choice at this index, as the choices are shown (or the book, picking a book).
    case choose(Int)
    /// Checks the answer, or moves on: Continue, Done reading, Got it, Done.
    case submit
    /// Hands in the writing, or saves a reflection.
    case handIn
    /// Plays the prompt again.
    case replay
    case replaySlowly
    /// "Don't know" (or "Haven't learned this" in a placement).
    case dontKnow
    /// Picks A or B in a blind comparison.
    case pick(Int)
}

/// A key and the modifiers held with it, bound to what it does on the step on screen.
public struct SessionKeyBinding: Hashable, Sendable, Identifiable {
    public enum Key: Hashable, Sendable {
        case character(Character)
        case `return`, space
    }

    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
    }

    public var key: Key
    public var modifiers: Modifiers
    public var action: SessionKey

    public init(_ key: Key, _ action: SessionKey, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
        self.action = action
    }

    public var id: String { "\(label) \(action)" }

    /// The key as a hint shows it: "1", "A", "Space", "↩", "⌘↩", "⌥R".
    public var label: String {
        let held = (modifiers.contains(.option) ? "⌥" : "") + (modifiers.contains(.command) ? "⌘" : "")
        switch key {
        case .character(let character): return held + String(character).uppercased()
        case .return: return held + "↩"
        case .space: return held + "Space"
        }
    }
}

/// The keyboard in a session: 1–9 pick a choice (in the order shown, whatever order the engine
/// shuffled them into), Return checks or moves on, ⌘Return hands in writing, Space or R plays the
/// prompt again and ⌥R plays it slower, ? or ⌘D is "Don't know", A and B pick in a comparison.
/// Escape, for End, belongs to the session's own toolbar.
///
/// Typing never fights the shortcuts: while a text field has the keyboard only keys held with ⌘
/// are bound, so digits, letters, spaces and question marks go into the answer, and Return goes to
/// the field (which checks a typed answer itself).
public enum SessionKeys {
    /// Choices past nine have no key.
    public static let maxChoices = 9

    /// The keys that do something on a step now. `typing` is whether a text field on it has the
    /// keyboard; `canHandIn` whether there's writing to hand in (or a reflection to save).
    public static func bindings(
        step: StudyRun.Step?, feedback: StudyRun.Feedback?, typing: Bool = false, canHandIn: Bool = false
    ) -> [SessionKeyBinding] {
        var keys: [SessionKeyBinding] = []
        func choices(_ count: Int) {
            for index in 0..<min(count, maxChoices) { keys.append(SessionKeyBinding(.character(digit(index)), .choose(index))) }
        }
        func replay() {
            keys += [
                SessionKeyBinding(.space, .replay), SessionKeyBinding(.character("r"), .replay),
                SessionKeyBinding(.character("r"), .replaySlowly, modifiers: .option),
            ]
        }
        func dontKnow() {
            keys += [SessionKeyBinding(.character("?"), .dontKnow), SessionKeyBinding(.character("d"), .dontKnow, modifiers: .command)]
        }
        let submit = SessionKeyBinding(.return, .submit)

        switch step {
        case nil:
            keys.append(submit)
        case .lesson(let lesson):
            keys.append(submit)
            switch lesson {
            case .word, .kana: replay()
            case .topic, .skill: break
            }
        case .question(let question):
            if let feedback {
                // A test moves on by itself: it measures, it doesn't teach.
                if feedback.question.kind != .test { keys.append(submit) }
            } else {
                switch question.answer {
                case .choice: choices(question.choices.count)
                case .number: keys.append(submit)
                }
                if question.allowsDontKnow { dontKnow() }
            }
            if case .audio = question.prompt { replay() }
        case .speak(let task):
            if feedback != nil {
                keys.append(submit)
            } else {
                // Saying: Return starts the microphone, and stops it to check what was heard.
                keys.append(submit)
                if task.kind == .test { dontKnow() }
            }
            if case .audio = task.prompt { replay() }
        case .passage, .read:
            keys.append(submit)
        case .pickBook(let options):
            choices(options.count)
        case .reflect:
            if canHandIn { keys.append(SessionKeyBinding(.return, .handIn, modifiers: .command)) }
        case .compose(let task):
            if task.reviewing != nil {
                keys.append(submit)
            } else if canHandIn {
                keys.append(SessionKeyBinding(.return, .handIn, modifiers: .command))
            }
        case .compare:
            keys += [SessionKeyBinding(.character("a"), .pick(0)), SessionKeyBinding(.character("b"), .pick(1))]
        }
        return typing ? keys.filter { $0.modifiers.contains(.command) } : keys
    }

    /// The key shown beside a choice: "1" to "9" in the order shown, nil past nine.
    public static func label(choice index: Int) -> String? {
        (0..<maxChoices).contains(index) ? String(digit(index)) : nil
    }

    /// The key for a binding's action, if one is bound: for a hint on its button.
    public static func label(for action: SessionKey, in bindings: [SessionKeyBinding]) -> String? {
        bindings.first { $0.action == action }?.label
    }

    private static func digit(_ index: Int) -> Character { Character(String(index + 1)) }
}

/// How a step uses a wide window: the Mac, an iPad in landscape or a wide split, Vision Pro.
public enum SessionLayout {
    /// A prompt this long (or longer) reads best beside its answers.
    static let longPrompt = 160

    /// Whether a question's prompt sits beside its answers: a chart, or a prompt long enough to
    /// read as a passage (a word problem, a sentence to make sense of). One word over its choices
    /// stays in one column, centred.
    public static func sideBySide(_ question: Question) -> Bool {
        if question.figure != nil { return true }
        let length: Int
        switch question.prompt {
        case .text(let text), .math(let text): length = text.count
        case .scaffolded(let text): length = text.text.count
        case .foreign(let text, _, _): length = text.count
        case .audio: return false
        }
        return length >= longPrompt
    }

    /// Whether a writing task has something to work from beside the editor: the passage, the text
    /// being rewritten, or the notes for a Franklin rewrite. A prompt alone sits above it.
    public static func sideBySide(_ task: WritingTask) -> Bool { task.reviewing == nil && (task.showsSource || task.notes != nil) }
}
