import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which model answers.
public enum AIEngine: String, Sendable, Codable {
    case onDevice
    case privateCloud
}

/// How much a job asks of the model. Light jobs (naming a book from its cover's text) stay on the
/// device; heavy ones (notes on a page of writing, a blind comparison) prefer Private Cloud
/// Compute when it's allowed, and fall back to the device when it isn't.
public enum AIWeight: Sendable {
    case light, heavy
}

/// What's usable right now, as a snapshot, so the choices below are pure and testable.
public struct AIAvailability: Sendable, Equatable {
    public var onDevice: Bool
    public var privateCloud: Bool
    /// Why nothing can answer, in words for the person. Nil when something can.
    public var reason: String?

    public init(onDevice: Bool, privateCloud: Bool, reason: String? = nil) {
        self.onDevice = onDevice
        self.privateCloud = privateCloud
        self.reason = reason
    }

    public var any: Bool { onDevice || privateCloud }
}

/// Why a request couldn't be answered. Messages are written for the person.
public enum AIError: Error, Equatable, Sendable {
    case unavailable(String)
    case busy
    case network
    case quotaReached(Date?)
    case tooLong
    case refused
    case failed(String)

    public var message: String {
        switch self {
        case .unavailable(let reason): reason
        case .busy: "Apple Intelligence is busy. Try again in a moment."
        case .network: "Private Cloud Compute needs a connection. Try again when you're online."
        case .quotaReached: "Private Cloud Compute has reached today's limit. The device model will answer what it can."
        case .tooLong: "That's longer than the model can read at once."
        case .refused: "The model declined this one."
        case .failed(let reason): reason
        }
    }
}

/// The pure choices: which engine first, and what to try after a failure.
public enum AIRouting {
    public static func engine(_ weight: AIWeight, in state: AIAvailability) -> AIEngine? {
        switch weight {
        case .light: state.onDevice ? .onDevice : (state.privateCloud ? .privateCloud : nil)
        case .heavy: state.privateCloud ? .privateCloud : (state.onDevice ? .onDevice : nil)
        }
    }

    /// The other engine, when the first failed in a way the other might not.
    public static func fallback(after error: AIError, from engine: AIEngine, in state: AIAvailability) -> AIEngine? {
        switch (engine, error) {
        case (.privateCloud, .network), (.privateCloud, .quotaReached), (.privateCloud, .unavailable), (.privateCloud, .busy),
            (.privateCloud, .failed):
            return state.onDevice ? .onDevice : nil
        case (.onDevice, .tooLong), (.onDevice, .busy), (.onDevice, .unavailable), (.onDevice, .failed):
            return state.privateCloud ? .privateCloud : nil
        default:
            return nil
        }
    }
}

/// The apps' one interface to a language model. Every AI call goes through here.
public actor SystemAI {
    /// Answers one request on one engine: the engine, instructions, prompt and token limit.
    typealias Runner = @Sendable (AIEngine, String, String, Int) async throws -> String

    public let allowCloud: Bool
    private let currentAvailability: @Sendable (Bool) -> AIAvailability
    private let runner: Runner

    public init(allowCloud: Bool) {
        self.init(
            allowCloud: allowCloud, availability: { SystemAI.availability(allowCloud: $0) },
            runner: { engine, instructions, prompt, maxTokens in
                try await SystemAI.run(engine, instructions: instructions, prompt: prompt, maxTokens: maxTokens)
            })
    }

    /// A model and availability of the caller's choosing, for tests.
    init(allowCloud: Bool, availability: @escaping @Sendable (Bool) -> AIAvailability, runner: @escaping Runner) {
        self.allowCloud = allowCloud
        self.currentAvailability = availability
        self.runner = runner
    }

    /// Private Cloud Compute needs Apple's managed entitlement (com.apple.developer.private-cloud-compute).
    /// Without it the framework still reports it available, then stops the app on the first request
    /// with a fatal error, so it's used only when the app says it has the entitlement: `SystemAIPrivateCloud`
    /// set to true in its Info.plist. Until then, heavy jobs run on the device.
    public static var privateCloudEntitled: Bool { Bundle.main.object(forInfoDictionaryKey: "SystemAIPrivateCloud") as? Bool ?? false }

    /// What can answer now. Needs iOS 27 / macOS 27 with Apple Intelligence; Private Cloud Compute
    /// also needs the setting on and the entitlement.
    public static func availability(allowCloud: Bool) -> AIAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) { return FoundationBackend.availability(allowCloud: allowCloud) }
        #endif
        return AIAvailability(onDevice: false, privateCloud: false, reason: "This needs Apple Intelligence on iOS 27.")
    }

    /// A reply in plain text: `instructions` say who the model is and how to answer; `prompt` is
    /// the job. Throws `AIError`, or `CancellationError` when the task is cancelled.
    ///
    /// Each engine is tried at most once: the first, then the other if the failure is one it might
    /// not share. When both fail, the second engine's error is thrown, rather than bouncing between
    /// them for as long as both keep failing.
    public func respond(instructions: String, prompt: String, weight: AIWeight, maxTokens: Int = 600) async throws -> String {
        let state = currentAvailability(allowCloud)
        guard var engine = AIRouting.engine(weight, in: state) else {
            throw AIError.unavailable(state.reason ?? "Apple Intelligence isn't available.")
        }
        var tried: Set<AIEngine> = [engine]
        while true {
            try Task.checkCancellation()
            do {
                return try await runner(engine, instructions, prompt, maxTokens)
            } catch let error as AIError {
                guard let next = AIRouting.fallback(after: error, from: engine, in: state), tried.insert(next).inserted else { throw error }
                engine = next
            }
        }
    }

    static func run(_ engine: AIEngine, instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            return try await FoundationBackend.respond(engine, instructions: instructions, prompt: prompt, maxTokens: maxTokens)
        }
        #endif
        throw AIError.unavailable("This needs Apple Intelligence on iOS 27.")
    }
}

#if canImport(FoundationModels)
/// Apple's Foundation Models behind the interface: the system model on device, Private Cloud
/// Compute through the same session API.
@available(iOS 27.0, macOS 27.0, *)
enum FoundationBackend {
    static func availability(allowCloud: Bool) -> AIAvailability {
        var reason: String?
        var device = false
        switch SystemLanguageModel.default.availability {
        case .available: device = true
        case .unavailable(.deviceNotEligible): reason = "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): reason = "Turn on Apple Intelligence in Settings to use this."
        case .unavailable(.modelNotReady): reason = "Apple Intelligence is still getting ready. Try again later."
        case .unavailable: reason = "Apple Intelligence isn't available right now."
        }
        var cloud = false
        if allowCloud && SystemAI.privateCloudEntitled {
            let pcc = PrivateCloudComputeLanguageModel()
            cloud = pcc.isAvailable && !pcc.quotaUsage.isLimitReached
        }
        return AIAvailability(onDevice: device, privateCloud: cloud, reason: device || cloud ? nil : reason)
    }

    static func respond(_ engine: AIEngine, instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        let model: any LanguageModel = engine == .onDevice ? SystemLanguageModel.default : PrivateCloudComputeLanguageModel()
        let session = LanguageModelSession(model: model, instructions: instructions)
        var retries = 0
        while true {
            do {
                let reply = try await session.respond(to: prompt, options: GenerationOptions(maximumResponseTokens: max(64, min(maxTokens, 4096))))
                return reply.content
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let reason = classify(error)
                guard reason == .busy, retries < 2 else { throw reason }
                retries += 1
                try await Task.sleep(for: .milliseconds(retries == 1 ? 400 : 1000))
            }
        }
    }

    static func classify(_ error: any Error) -> AIError {
        switch error {
        case let error as AIError:
            return error
        case let error as LanguageModelError:
            switch error {
            case .rateLimited, .timeout: return .busy
            case .guardrailViolation, .refusal: return .refused
            case .contextSizeExceeded: return .tooLong
            case .unsupportedLanguageOrLocale: return .unavailable("Apple Intelligence doesn't support this language yet.")
            default: return .failed(error.localizedDescription)
            }
        case let error as LanguageModelSession.Error:
            switch error {
            case .concurrentRequests: return .busy
            default: return .failed(error.localizedDescription)
            }
        case let error as PrivateCloudComputeLanguageModel.Error:
            switch error {
            case .networkFailure: return .network
            case .quotaLimitReached(let quota): return .quotaReached(quota.resetDate)
            case .serviceUnavailable: return .unavailable("Private Cloud Compute is unavailable right now. Try again later.")
            @unknown default: return .failed(error.localizedDescription)
            }
        default:
            return .failed(error.localizedDescription)
        }
    }
}
#endif
