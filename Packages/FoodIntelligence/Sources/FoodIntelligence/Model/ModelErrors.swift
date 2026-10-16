import Foundation
import FoundationModels

@available(iOS 27.0, macOS 27.0, *)
enum ModelErrors {
    /// The person-facing reason a request failed, so the app can offer a retry or an explanation.
    /// Cancellation is not an error here and is passed through by callers.
    static func classify(_ error: any Error) -> MealAIError {
        switch error {
        case let error as MealAIError:
            return error
        case let error as LanguageModelError:
            switch error {
            case .rateLimited, .timeout: return .busy
            case .guardrailViolation, .refusal: return .refused
            case .contextSizeExceeded: return .tooLong
            case .unsupportedLanguageOrLocale: return .unavailable("Apple Intelligence doesn't support this language yet.")
            case .unsupportedCapability: return .unavailable("This model can't read photos. Describe the meal instead.")
            default: return .failed(error.localizedDescription)
            }
        case let error as LanguageModelSession.Error:
            switch error {
            case .concurrentRequests: return .busy
            default: return .failed(error.localizedDescription)
            }
        case let error as SystemLanguageModel.Error:
            switch error {
            case .assetsUnavailable: return .unavailable("Apple Intelligence is still getting ready. Try again later.")
            @unknown default: return .failed(error.localizedDescription)
            }
        case let error as PrivateCloudComputeLanguageModel.Error:
            switch error {
            case .networkFailure: return .network
            case .quotaLimitReached(let quota): return .quotaReached(quota.resetDate)
            case .serviceUnavailable: return .unavailable("Private Cloud Compute is unavailable right now. Try again later.")
            @unknown default: return .failed(error.localizedDescription)
            }
        case is GeneratedContent.ParsingError:
            return .failed("The model's answer couldn't be read. Try again.")
        default:
            return .failed(error.localizedDescription)
        }
    }
}
