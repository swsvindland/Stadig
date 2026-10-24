import Foundation

/// How the voice says something. Short things go slower: a lone kana from the voice is a tenth of a
/// second, and a word at the voice's own speed runs by before it's heard. Sentences stay near
/// natural speed. Everything gets a pause either side, so the first sound plays once the speaker or
/// headphones are awake and the last has played out before the audio is handed back.
public struct SpokenPace: Hashable, Sendable {
    public enum Length: Hashable, Sendable {
        /// One kana, or a letter or two: a sound on its own.
        case sound
        /// A word or a short phrase.
        case word
        case sentence
    }

    public var length: Length
    /// Speed as a share of the voice's own.
    public var rate: Double
    /// Silence asked for before and after, in milliseconds. Apple's voices trim about 100 ms of
    /// each, so 250 puts about 150 ms of quiet before the first sound.
    public var pause: Int

    public static let pauseMilliseconds = 250

    public static func pace(_ text: String, language: Language, slow: Bool = false) -> SpokenPace {
        let length = length(text, language: language)
        let rate: Double =
            switch length {
            case .sound: slow ? 0.3 : 0.5
            case .word: slow ? 0.55 : 0.8
            case .sentence: slow ? 0.65 : 0.9
            }
        return SpokenPace(length: length, rate: rate, pause: pauseMilliseconds)
    }

    /// Japanese has no spaces, so its length is in characters; Spanish counts words.
    static func length(_ text: String, language: Language) -> Length {
        let letters = text.filter { $0.isLetter || $0.isNumber }
        switch language {
        case .japanese:
            if KanaTable.byKana[letters] != nil || letters.count <= 1 { return .sound }
            return letters.count <= 6 ? .word : .sentence
        case .spanish:
            if letters.count <= 2 { return .sound }
            let words = text.split { $0.isWhitespace }.count
            return words <= 2 ? .word : .sentence
        }
    }

    /// The text as speech markup (SSML) for Apple's voices: the pause, the text at its rate, the
    /// pause again.
    public func markup(_ text: String) -> String {
        let percent = Int((rate * 100).rounded())
        return "<speak><break time=\"\(pause)ms\"/><prosody rate=\"\(percent)%\">\(Self.escaped(text))</prosody><break time=\"\(pause)ms\"/></speak>"
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
