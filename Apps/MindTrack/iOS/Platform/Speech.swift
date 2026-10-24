import AVFoundation
import Foundation
import MindEngine
import OSLog
import Observation

/// The language being learned, read aloud on the device with the best voice installed for it.
/// Enhanced and premium voices (`voicesSettings` says where to get them) sound far more natural.
/// Each utterance is paced and padded by `SpokenPace`.
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
            (candidates.isEmpty ? fallback : candidates).max { Self.rank($0) < Self.rank($1) }
            ?? AVSpeechSynthesisVoice(language: locale)
        voices[language] = .some(voice)
        return voice
    }

    /// Apple's natural voices before the Eloquence and novelty ones, which are made to sound
    /// synthetic and sit at the same default quality (so a tie would go to whichever the system
    /// lists first); then premium, enhanced, compact, super-compact.
    private static func rank(_ voice: AVSpeechSynthesisVoice) -> (natural: Int, quality: Int, size: Int) {
        let synthetic = voice.voiceTraits.contains(.isNoveltyVoice) || voice.identifier.contains(".eloquence.")
        return (synthetic ? 0 : 1, voice.quality.rawValue, voice.identifier.contains(".super-compact.") ? 0 : 1)
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
        let utterance = Self.utterance(text, pace: SpokenPace.pace(text, language: language, slow: slow))
        utterance.voice = voice(language)
        pending += 1
        synthesizer.speak(utterance)
    }

    /// As markup, whose pauses are silence the voice plays, so the output is already running when
    /// the first sound comes (the utterance's own delays are only waits). The rate is in the markup
    /// too, since a markup utterance ignores its `rate`. Plain text at the same rate if the markup
    /// is turned down.
    private static func utterance(_ text: String, pace: SpokenPace) -> AVSpeechUtterance {
        if let marked = AVSpeechUtterance(ssmlRepresentation: pace.markup(text)) { return marked }
        appLog.notice("The voice turned down the markup for an utterance; speaking it plain")
        let plain = AVSpeechUtterance(string: text)
        plain.rate = AVSpeechUtteranceDefaultSpeechRate * Float(pace.rate)
        plain.preUtteranceDelay = Double(pace.pause) / 1000
        plain.postUtteranceDelay = Double(pace.pause) / 1000
        return plain
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
