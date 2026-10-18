import AVFoundation
import Foundation
import Observation
import OSLog
import Speech
import MindEngine

/// Listens for a spoken answer in the language being learned, on the device: Apple's SpeechAnalyzer
/// with a transcriber for the language's locale, its model downloaded the first time a language is
/// used. Nothing is sent anywhere. The session's runner marks what it heard.
@MainActor @Observable
final class SpeechRecognizer {
    static let shared = SpeechRecognizer()

    enum Status: Equatable {
        case idle
        case preparing(String)
        case listening
        case finishing
        case unavailable(String)
    }

    private(set) var status: Status = .idle
    /// What's been heard so far, updating as it listens.
    private(set) var heard = ""
    /// When `heard` last changed, for stopping after a pause.
    @ObservationIgnored private(set) var lastChange = Date()

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var input: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var results: Task<Void, Never>?
    @ObservationIgnored private var settled = ""

    var isListening: Bool { status == .listening }

    /// Whether this device can recognise a language on the device, without asking for anything.
    func supports(_ language: Language) async -> Bool {
        let locale = Locale(identifier: language.pack.locale)
        if SpeechTranscriber.isAvailable, await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil { return true }
        return await DictationTranscriber.supportedLocale(equivalentTo: locale) != nil
    }

    /// The microphone and speech recognition, asked for once.
    func authorise() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        return await Self.speechAuthorisation() == .authorized
    }

    var permissionDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied || SFSpeechRecognizer.authorizationStatus() == .denied
    }

    /// Starts listening in a language.
    func start(_ language: Language) async {
        guard analyzer == nil else { return }
        heard = ""
        settled = ""
        guard await authorise() else {
            status = .unavailable("Allow the microphone and speech recognition for Mind Track in Settings to answer out loud.")
            return
        }
        let name = language.pack.name
        let locale = Locale(identifier: language.pack.locale)
        let module: any SpeechModule
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults],
                                                attributeOptions: [])
            module = transcriber
            results = Task { [weak self] in
                do {
                    for try await result in transcriber.results { self?.receive(String(result.text.characters), final: result.isFinal) }
                } catch {
                    appLog.error("Speech results ended: \(error.localizedDescription)")
                }
            }
        } else if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = DictationTranscriber(locale: supported, preset: .progressiveShortDictation)
            module = transcriber
            results = Task { [weak self] in
                do {
                    for try await result in transcriber.results { self?.receive(String(result.text.characters), final: result.isFinal) }
                } catch {
                    appLog.error("Speech results ended: \(error.localizedDescription)")
                }
            }
        } else {
            status = .unavailable("This device can't recognise \(name) on the device.")
            return
        }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                status = .preparing("Getting \(name) speech recognition ready…")
                try await request.downloadAndInstall()
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                throw SpeechError.noFormat
            }
            let analyzer = SpeechAnalyzer(modules: [module])
            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            self.analyzer = analyzer
            input = continuation
            try Self.record()
            try startEngine(converting: format, into: continuation)
            try await analyzer.start(inputSequence: stream)
            lastChange = Date()
            status = .listening
        } catch {
            appLog.error("Couldn't start listening: \(error.localizedDescription)")
            await cancel()
            status = .unavailable("Speech recognition couldn't start. Try again in a moment.")
        }
    }

    /// Stops listening and returns everything heard.
    func finish() async -> String {
        guard let analyzer else { return heard }
        status = .finishing
        stopEngine()
        input?.finish()
        input = nil
        do { try await analyzer.finalizeAndFinishThroughEndOfInput() } catch { appLog.error("Speech didn't finish: \(error.localizedDescription)") }
        await results?.value
        self.analyzer = nil
        results = nil
        Self.play()
        status = .idle
        return heard
    }

    /// Stops without an answer (the step was left).
    func cancel() async {
        stopEngine()
        input?.finish()
        input = nil
        if let analyzer { await analyzer.cancelAndFinishNow() }
        analyzer = nil
        results?.cancel()
        results = nil
        Self.play()
        if case .unavailable = status { return }
        status = .idle
    }

    private func receive(_ text: String, final: Bool) {
        if final {
            settled += text
            heard = settled
        } else {
            heard = settled + text
        }
        lastChange = Date()
    }

    // MARK: Audio

    private func startEngine(converting format: AVAudioFormat, into continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let natural = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 4096, format: natural, block: Self.tap(BufferConverter(from: natural, to: format), continuation))
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func stopEngine() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
    }

    /// The microphone tap runs on the audio thread, so it's made away from the main actor.
    nonisolated private static func tap(_ converter: BufferConverter,
                                        _ continuation: AsyncStream<AnalyzerInput>.Continuation) -> AVAudioNodeTapBlock {
        { buffer, _ in
            if let converted = converter.convert(buffer) { continuation.yield(AnalyzerInput(buffer: converted)) }
        }
    }

    nonisolated private static func speechAuthorisation() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private static func record() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Back to playback for the voice, as `Speech` sets it up.
    private static func play() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    enum SpeechError: Error { case noFormat }
}

/// Converts microphone buffers to the analyzer's format. Used only on the audio thread.
nonisolated private final class BufferConverter: @unchecked Sendable {
    let converter: AVAudioConverter?
    let format: AVAudioFormat

    init(from source: AVAudioFormat, to format: AVAudioFormat) {
        self.format = format
        converter = source == format ? nil : AVAudioConverter(from: source, to: format)
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        let supplied = Supplied()
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied.done {
                status.pointee = .noDataNow
                return nil
            }
            supplied.done = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }

    nonisolated private final class Supplied: @unchecked Sendable { var done = false }
}
