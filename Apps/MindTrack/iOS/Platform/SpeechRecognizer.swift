import AVFoundation
import Foundation
import MindEngine
import OSLog
import Observation
import Speech
import SystemCore

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
    /// Moves with every start, finish and cancel. A start checks it after each wait (permission, the
    /// model's download, the analyzer starting) and gives up if it moved: the step was left meanwhile.
    @ObservationIgnored private var attempt = 0
    /// A start is on its way, so a second tap doesn't start another.
    @ObservationIgnored private var starting = false

    var isListening: Bool { status == .listening }

    /// Getting ready or wrapping up: the microphone button waits.
    var isBusy: Bool {
        switch status {
        case .preparing, .finishing: true
        case .idle, .listening, .unavailable: false
        }
    }

    /// Whether this device can recognise a language on the device, without asking for anything.
    func supports(_ language: Language) async -> Bool {
        let locale = Locale(identifier: language.pack.locale)
        if SpeechTranscriber.isAvailable, await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil { return true }
        return await DictationTranscriber.supportedLocale(equivalentTo: locale) != nil
    }

    /// The microphone and speech recognition, asked for once. Never under tests or UI tests, whose
    /// runs a permission alert would block: speaking is skipped there (or faked, with `-fakeSpeech`).
    func authorise() async -> Bool {
        guard !LaunchOptions.current.isQuiet else { return false }
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        return await Self.speechAuthorisation() == .authorized
    }

    var permissionDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied || SFSpeechRecognizer.authorizationStatus() == .denied
    }

    /// Starts listening in a language.
    func start(_ language: Language) async {
        guard analyzer == nil, !starting else { return }
        starting = true
        attempt += 1
        let mine = attempt
        defer { if attempt == mine { starting = false } }
        heard = ""
        settled = ""
        let authorised = await authorise()
        guard attempt == mine else { return }
        guard authorised else {
            let settings = Platform.isMac ? "System Settings, under Privacy & Security" : "Settings"
            status = .unavailable("Allow the microphone and speech recognition for Stadig Mind in \(settings) to answer out loud.")
            return
        }
        let name = language.pack.name
        let locale = Locale(identifier: language.pack.locale)
        let module: any SpeechModule
        // What reads the transcriber's results, started only once listening really begins.
        let listen: () -> Task<Void, Never>
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = SpeechTranscriber(
                locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults],
                attributeOptions: [])
            module = transcriber
            listen = { [weak self] in
                Task { [weak self] in
                    do {
                        for try await result in transcriber.results { self?.receive(String(result.text.characters), final: result.isFinal) }
                    } catch {
                        appLog.error("Speech results ended: \(error.localizedDescription)")
                    }
                }
            }
        } else if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = DictationTranscriber(locale: supported, preset: .progressiveShortDictation)
            module = transcriber
            listen = { [weak self] in
                Task { [weak self] in
                    do {
                        for try await result in transcriber.results { self?.receive(String(result.text.characters), final: result.isFinal) }
                    } catch {
                        appLog.error("Speech results ended: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            guard attempt == mine else { return }
            status = .unavailable("This device can't recognise \(name) on the device.")
            return
        }
        guard attempt == mine else { return }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                guard attempt == mine else { return }
                status = .preparing("Getting \(name) speech recognition ready…")
                // The first time a language is used this can take a while, and the step may be left.
                try await request.downloadAndInstall()
                guard attempt == mine else { return }
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                throw SpeechError.noFormat
            }
            guard attempt == mine else { return }
            let analyzer = SpeechAnalyzer(modules: [module])
            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            self.analyzer = analyzer
            input = continuation
            results = listen()
            try AudioSession.startListening()
            try startEngine(converting: format, into: continuation)
            try await analyzer.start(inputSequence: stream)
            // A cancel while the analyzer started has torn it down already.
            guard attempt == mine else { return }
            lastChange = Date()
            status = .listening
        } catch {
            guard attempt == mine else { return }
            appLog.error("Couldn't start listening: \(error.localizedDescription)")
            await cancel()
            status = .unavailable("Speech recognition couldn't start. Try again in a moment.")
        }
    }

    /// Stops listening and returns everything heard.
    func finish() async -> String {
        guard let analyzer else {
            // Nothing is listening, so nothing should say it is.
            if status == .listening { status = .idle }
            return heard
        }
        attempt += 1
        let mine = attempt
        starting = false
        status = .finishing
        stopEngine()
        input?.finish()
        input = nil
        let results = results
        do { try await analyzer.finalizeAndFinishThroughEndOfInput() } catch { appLog.error("Speech didn't finish: \(error.localizedDescription)") }
        await results?.value
        let said = heard
        // Cancelled meanwhile (the step was left), and perhaps listening again since: leave that be.
        guard attempt == mine else { return said }
        self.analyzer = nil
        self.results = nil
        AudioSession.stopListening()
        status = .idle
        return said
    }

    /// Stops without an answer (the step was left), including a start still on its way.
    func cancel() async {
        attempt += 1
        starting = false
        stopEngine()
        input?.finish()
        input = nil
        let analyzer = analyzer
        self.analyzer = nil
        results?.cancel()
        results = nil
        AudioSession.stopListening()
        if case .unavailable = status {} else { status = .idle }
        if let analyzer { await analyzer.cancelAndFinishNow() }
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
    nonisolated private static func tap(
        _ converter: BufferConverter,
        _ continuation: AsyncStream<AnalyzerInput>.Continuation
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            if let converted = converter.convert(buffer) { continuation.yield(AnalyzerInput(buffer: converted)) }
        }
    }

    nonisolated private static func speechAuthorisation() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
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
