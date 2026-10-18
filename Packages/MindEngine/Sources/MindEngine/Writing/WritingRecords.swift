import Foundation

/// The kinds of writing to improve. More than one allowed; creative by default.
public enum WritingKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case creative, practical, argument

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .creative: "Creative"
        case .practical: "Practical"
        case .argument: "Argument and essay"
        }
    }

    public var detail: String {
        switch self {
        case .creative: "Stories, scenes, description."
        case .practical: "Emails, docs and messages that are clear the first time."
        case .argument: "Making a case and backing it up."
        }
    }
}

/// A writing exercise's type.
public enum WritingExercise: String, CaseIterable, Codable, Sendable {
    /// Franklin method, part one: read a passage, take brief notes.
    case franklinNotes
    /// Franklin method, part two (later): rewrite the passage from the notes, then compare.
    case franklinRewrite
    /// A short creative prompt (about three paragraphs).
    case prompt
    /// Rewrite a scene: another point of view, tense or mood.
    case sceneRewrite
    /// A practical task: rewrite a terse email clearly.
    case practical
    /// An argument: make a case in a few paragraphs.
    case argument
    /// The term's benchmark prompt, repeated every few months like a strength test.
    case benchmark
}

/// How a piece was written. Handwriting is read with on-device text recognition; typed and
/// handwritten count the same.
public enum WritingSource: String, Codable, Sendable {
    case typed, handwritten
}

/// A writing task in a session.
public struct WritingTask: Hashable, Sendable, Identifiable {
    public var id: String
    public var exercise: WritingExercise
    public var instruction: String
    /// The passage to read (Franklin method), or the text to rewrite.
    public var source: String?
    /// Where the source came from: a book's title and author.
    public var sourceCredit: String?
    /// Notes taken earlier, for a Franklin rewrite.
    public var notes: String?
    public var minutes: Int

    public init(id: String, exercise: WritingExercise, instruction: String, source: String? = nil, sourceCredit: String? = nil,
                notes: String? = nil, minutes: Int) {
        self.id = id
        self.exercise = exercise
        self.instruction = instruction
        self.source = source
        self.sourceCredit = sourceCredit
        self.notes = notes
        self.minutes = minutes
    }
}

/// An old and a new piece shown unlabelled, in random order: which is stronger?
public struct BlindPair: Hashable, Sendable, Identifiable {
    public var id: String
    public var first: WritingPiece
    public var second: WritingPiece
    public var prompt: String

    public init(id: String, first: WritingPiece, second: WritingPiece, prompt: String) {
        self.id = id
        self.first = first
        self.second = second
        self.prompt = prompt
    }
}

/// A piece of writing and what's known about it. Feedback is comments, never a grade; the
/// metrics are deterministic and shown only as trends.
public struct WritingPiece: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var exercise: WritingExercise
    /// Named `writingKind` because a record's static `kind` would hide a property called `kind`.
    public var writingKind: WritingKind
    /// The prompt or task text as it was shown.
    public var prompt: String
    public var text: String
    public var source: WritingSource
    /// Franklin method notes, kept for the rewrite.
    public var notes: String?
    /// The AI's few specific notes (grammar and spelling, clarity, flow, craft). Nil until given.
    public var feedback: String?
    /// Errors per 100 words, vocabulary range, sentence-length variety and the like.
    public var metrics: [String: Double]
    public var updatedAt: Date

    public init(id: UUID = UUID(), date: Date, exercise: WritingExercise, writingKind: WritingKind, prompt: String, text: String,
                source: WritingSource = .typed, notes: String? = nil, feedback: String? = nil, metrics: [String: Double] = [:],
                updatedAt: Date = Date()) {
        self.id = id
        self.date = date
        self.exercise = exercise
        self.writingKind = writingKind
        self.prompt = prompt
        self.text = text
        self.source = source
        self.notes = notes
        self.feedback = feedback
        self.metrics = metrics
        self.updatedAt = updatedAt
    }

    public var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
}

/// The result of a blind side-by-side: which piece the person picked, and the AI's second opinion.
public struct BlindComparison: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var older: UUID
    public var newer: UUID
    /// Nil until picked.
    public var pickedNewer: Bool?
    /// The AI's blind pick, when it gave one.
    public var aiPickedNewer: Bool?
    public var updatedAt: Date

    public init(id: UUID = UUID(), date: Date, older: UUID, newer: UUID, pickedNewer: Bool? = nil, aiPickedNewer: Bool? = nil,
                updatedAt: Date = Date()) {
        self.id = id
        self.date = date
        self.older = older
        self.newer = newer
        self.pickedNewer = pickedNewer
        self.aiPickedNewer = aiPickedNewer
        self.updatedAt = updatedAt
    }
}
