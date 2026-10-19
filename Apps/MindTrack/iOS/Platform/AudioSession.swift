import AVFoundation
import Foundation
import OSLog

/// The app's one audio session, shared by the voice (`Speech`) and the microphone
/// (`SpeechRecognizer`). Other audio, a podcast or music, is ducked only while one of them is using
/// it, and comes back up as soon as neither is. The Mac has no app audio session: there the voice
/// and the microphone simply play and record alongside whatever else is playing, so these do nothing.
@MainActor
enum AudioSession {
    private static var speaking = false
    private static var listening = false

    /// The voice is about to speak. It plays with the ringer off, like any learning app, and ducks
    /// other audio rather than stopping it. While the microphone is on, its session plays too.
    static func startSpeaking() {
        speaking = true
        guard !listening else { return }
        setPlayback()
    }

    /// The voice has nothing left to say.
    static func stopSpeaking() {
        speaking = false
        deactivateIfUnused()
    }

    static func startListening() throws {
        listening = true
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// The microphone is off: back to playback for the voice, or let other audio back up.
    static func stopListening() {
        guard listening else { return }
        listening = false
        setPlayback()
        deactivateIfUnused()
    }

    private static func setPlayback() {
        #if !os(macOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        } catch {
            appLog.error("Couldn't set up the audio session for the voice: \(error.localizedDescription)")
        }
        #endif
    }

    private static func deactivateIfUnused() {
        guard !speaking, !listening else { return }
        #if !os(macOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            appLog.notice("Couldn't hand the audio back: \(error.localizedDescription)")
        }
        #endif
    }
}
