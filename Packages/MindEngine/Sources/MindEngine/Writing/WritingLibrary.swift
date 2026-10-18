import Foundation
import OSLog

/// A public-domain passage: read for the Franklin method, or the scene a rewrite starts from.
/// Built from Project Gutenberg by `Scripts/build-writing-passages.py`.
public struct WritingPassage: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var author: String
    public var year: Int?
    /// The reading ladder's id, when the book is on it.
    public var book: String?
    /// The kinds of writing it's a model for.
    public var kinds: [WritingKind]
    /// The ladder tier it reads at.
    public var tier: Int
    public var text: String
    /// Scene-rewrite instructions (creative passages only): another point of view, tense or mood.
    public var twists: [String]

    public init(id: String, title: String, author: String, year: Int? = nil, book: String? = nil, kinds: [WritingKind], tier: Int,
                text: String, twists: [String] = []) {
        self.id = id
        self.title = title
        self.author = author
        self.year = year
        self.book = book
        self.kinds = kinds
        self.tier = tier
        self.text = text
        self.twists = twists
    }

    public var credit: String { "\(title), \(author)" }
    public var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
}

/// A prompt or task written for Mind Track: a creative prompt, an argument, a practical rewrite
/// (with the text to rewrite) or a term's benchmark.
public struct WritingPrompt: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var exercise: WritingExercise
    public var writingKind: WritingKind
    public var text: String
    /// A practical task's original: the terse email or buried request to rewrite.
    public var source: String?
    /// A benchmark's fixed time, the same every term.
    public var minutes: Int?

    enum CodingKeys: String, CodingKey {
        case id, exercise, writingKind = "kind", text, source, minutes
    }

    public init(id: String, exercise: WritingExercise, writingKind: WritingKind, text: String, source: String? = nil, minutes: Int? = nil) {
        self.id = id
        self.exercise = exercise
        self.writingKind = writingKind
        self.text = text
        self.source = source
        self.minutes = minutes
    }
}

/// The passages and prompts that ship with the app.
public struct WritingLibrary: Sendable {
    public var passages: [WritingPassage]
    public var prompts: [WritingPrompt]

    public init(passages: [WritingPassage], prompts: [WritingPrompt]) {
        self.passages = passages
        self.prompts = prompts
    }

    private struct PassageFile: Decodable { var passages: [WritingPassage] }
    private struct PromptFile: Decodable { var prompts: [WritingPrompt] }

    public static let standard: WritingLibrary = {
        func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json"), let data = try? Data(contentsOf: url) else {
                mindLog.error("\(name, privacy: .public).json is missing")
                return nil
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                mindLog.error("\(name, privacy: .public).json is unreadable: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return WritingLibrary(passages: load("writing-passages", as: PassageFile.self)?.passages ?? [],
                              prompts: load("writing-prompts", as: PromptFile.self)?.prompts ?? [])
    }()

    public func passage(_ id: String) -> WritingPassage? { passages.first { $0.id == id } }
    public func prompt(_ id: String) -> WritingPrompt? { prompts.first { $0.id == id } }

    public func prompts(_ exercise: WritingExercise, _ kind: WritingKind) -> [WritingPrompt] {
        prompts.filter { $0.exercise == exercise && $0.writingKind == kind }
    }

    public func benchmark(_ kind: WritingKind) -> WritingPrompt? { prompts(.benchmark, kind).first }
}
