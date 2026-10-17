import AVFoundation
import Foundation

/// Japanese read aloud on the device, with the best Japanese voice installed. Enhanced and premium
/// voices (Settings → Accessibility → Spoken Content → Voices) sound far more natural.
@MainActor
final class Speech {
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionReady = false

    /// The best Japanese voice on this device.
    lazy var voice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language == "ja-JP" }
        .max { $0.quality.rawValue < $1.quality.rawValue }
        ?? AVSpeechSynthesisVoice(language: "ja-JP")

    var hasNaturalVoice: Bool { (voice?.quality ?? .default) != .default }
    var voiceName: String { voice?.name ?? "None installed" }

    func speak(_ text: String, slow: Bool = false) {
        if !sessionReady {
            // Plays with the ringer off, like any learning app, and ducks music rather than stopping it.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            sessionReady = true
        }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.7 : 0.92)
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
