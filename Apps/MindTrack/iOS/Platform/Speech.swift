import AVFoundation
import Foundation
import MindEngine
import Observation

/// The language being learned, read aloud on the device with the best voice installed for it.
/// Enhanced and premium voices (`voicesSettings` says where to get them) sound far more natural.
@MainActor @Observable
final class Speech: NSObject, AVSpeechSynthesizerDelegate {
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// Each language's voice, or nil when none is installed, until the installed voices change.
    @ObservationIgnored private var voices: [Language: AVSpeechSynthesisVoice?] = [:]
    /// Moves when the installed voices change (one downloaded in Settings), so screens that show a
    /// voice read it again.
    private var voicesChanged = 0
    /// Utterances asked for and not yet finished or cancelled; at none, the session is handed back.
    @ObservationIgnored private var pending = 0
    @ObservationIgnored private var voicesObserver: NotificationToken?

    override init() {
        super.init()
        synthesizer.delegate = self
        voicesObserver = NotificationToken.observe(AVSpeechSynthesizer.availableVoicesDidChangeNotification) { [weak self] in
            self?.voices.removeAll()
            self?.voicesChanged += 1
        }
    }

    /// The best voice on this device for a language.
    func voice(_ language: Language) -> AVSpeechSynthesisVoice? {
        _ = voicesChanged
        if let cached = voices[language] { return cached }
        let locale = language.pack.locale
        let code = String(locale.prefix(2))
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let candidates = installed.filter { $0.language == locale }
        let fallback = installed.filter { $0.language.hasPrefix(code) }
        let voice =
            (candidates.isEmpty ? fallback : candidates).max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: locale)
        voices[language] = .some(voice)
        return voice
    }

    /// Where the system keeps its downloadable voices, on this device.
    static var voicesSettings: String {
        Platform.isMac
            ? "System Settings → Accessibility → Spoken Content → System voice → Manage Voices"
            : "Settings → Accessibility → Spoken Content → Voices"
    }

    func hasNaturalVoice(_ language: Language) -> Bool { (voice(language)?.quality ?? .default) != .default }
    func voiceName(_ language: Language) -> String { voice(language)?.name ?? "None installed" }

    func speak(_ text: String, language: Language, slow: Bool = false) {
        AudioSession.startSpeaking()
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.7 : 0.92)
        utterance.postUtteranceDelay = 0.05
        pending += 1
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }

    /// Ducking is for while the voice speaks: once nothing is left to say, other audio comes back up.
    private func utteranceEnded() {
        pending = max(0, pending - 1)
        if pending == 0 { AudioSession.stopSpeaking() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }
}
