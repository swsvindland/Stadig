import Foundation

/// Something to say out loud: a word, a sentence, or a reply to a prompt. The app listens with
/// on-device speech recognition and hands back what it heard; the language's runner marks it.
public struct SpeakingTask: Hashable, Sendable, Identifiable {
    public var id: String
    public var key: CardKey
    public var language: Language
    public var kind: AttemptKind
    public var instruction: String
    /// What's shown or played: say this, repeat this, or answer this.
    public var prompt: Prompt
    /// Answers that count, in the language's script.
    public var expected: [String]
    public var expectedSeconds: Double

    public init(id: String, key: CardKey, language: Language, kind: AttemptKind, instruction: String, prompt: Prompt, expected: [String],
                expectedSeconds: Double) {
        self.id = id
        self.key = key
        self.language = language
        self.kind = kind
        self.instruction = instruction
        self.prompt = prompt
        self.expected = expected
        self.expectedSeconds = expectedSeconds
    }
}
