import Foundation

/// A language Mind Track teaches. One engine; languages are content.
public enum Language: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable {
    case japanese = "ja"
    case spanish = "es"

    public var id: String { rawValue }
    public var domain: Domain {
        switch self {
        case .japanese: .japanese
        case .spanish: .spanish
        }
    }
    public var pack: LanguagePack { LanguagePack.pack(self) }
}

/// A language's script layer: what has to be learned before (or beside) words.
public enum ScriptLayer: String, Codable, Sendable {
    /// Latin letters, nothing extra (Spanish).
    case none
    /// Hiragana and katakana, then kanji (Japanese).
    case kanaKanji
    /// Hangul, learnable in days (Korean).
    case hangul
}

/// Everything that makes a language a language here: its catalog, voice, speech recognition and
/// script layer. The skills, the scheduler and the tests are shared.
public struct LanguagePack: Hashable, Sendable {
    public var language: Language
    public var name: String
    /// BCP-47 locale for the voice and on-device speech recognition.
    public var locale: String
    /// The bundled catalog's file name, without ".db".
    public var catalog: String
    /// Card keys start with this: "jp.word.123".
    public var keyPrefix: String
    public var script: ScriptLayer

    public static func pack(_ language: Language) -> LanguagePack {
        switch language {
        case .japanese:
            LanguagePack(language: .japanese, name: "Japanese", locale: "ja-JP", catalog: "japanese", keyPrefix: "jp", script: .kanaKanji)
        case .spanish:
            LanguagePack(language: .spanish, name: "Spanish", locale: "es-ES", catalog: "spanish", keyPrefix: "es", script: .none)
        }
    }

    public static func language(prefix: String) -> Language? {
        Language.allCases.first { pack($0).keyPrefix == prefix }
    }
}

/// The four skills, tracked separately like separate lifts. Listening and speaking weigh most.
public enum LanguageSkill: String, CaseIterable, Codable, Sendable, Identifiable {
    case listening, speaking, reading, writing

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .listening: "Listening"
        case .speaking: "Speaking"
        case .reading: "Reading"
        case .writing: "Writing"
        }
    }

    /// Weight in the language's combined score.
    public var weight: Double {
        switch self {
        case .listening, .speaking: 0.3
        case .reading, .writing: 0.2
        }
    }
}
