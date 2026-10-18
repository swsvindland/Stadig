import AVFoundation
import Foundation
import MindEngine

/// The language being learned, read aloud on the device with the best voice installed for it.
/// Enhanced and premium voices (Settings → Accessibility → Spoken Content → Voices) sound far more
/// natural.
@MainActor
final class Speech {
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionReady = false
    private var voices: [Language: AVSpeechSynthesisVoice] = [:]

    /// The best voice on this device for a language.
    func voice(_ language: Language) -> AVSpeechSynthesisVoice? {
        if let voice = voices[language] { return voice }
        let locale = language.pack.locale
        let code = String(locale.prefix(2))
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == locale }
        let fallback = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(code) }
        let voice = (candidates.isEmpty ? fallback : candidates).max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: locale)
        voices[language] = voice
        return voice
    }

    func hasNaturalVoice(_ language: Language) -> Bool { (voice(language)?.quality ?? .default) != .default }
    func voiceName(_ language: Language) -> String { voice(language)?.name ?? "None installed" }

    func speak(_ text: String, language: Language, slow: Bool = false) {
        if !sessionReady {
            // Plays with the ringer off, like any learning app, and ducks music rather than stopping it.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            sessionReady = true
        }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.7 : 0.92)
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
