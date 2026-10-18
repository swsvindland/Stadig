import Foundation
import FoundationModels
import SystemCore

/// Which of Apple's models can recognize meals here, and why not when one can't.
public struct MealAIAvailability: Sendable, Equatable {
    /// The on-device model can read descriptions.
    public var onDevice: Bool
    /// The on-device model can also read photos.
    public var onDeviceVision: Bool
    /// Private Cloud Compute is allowed, entitled (see `PrivateCloud`) and available.
    public var privateCloud: Bool
    /// What the person can do about a missing ability; nil when photos and descriptions both work.
    public var reason: String?
    /// Private Cloud Compute can read photos.
    var privateCloudVision: Bool

    public init(onDevice: Bool, onDeviceVision: Bool, privateCloud: Bool, reason: String?) {
        self.init(
            onDevice: onDevice, onDeviceVision: onDeviceVision, privateCloud: privateCloud, privateCloudVision: privateCloud,
            reason: reason)
    }

    init(onDevice: Bool, onDeviceVision: Bool, privateCloud: Bool, privateCloudVision: Bool, reason: String?) {
        self.onDevice = onDevice
        self.onDeviceVision = onDeviceVision
        self.privateCloud = privateCloud
        self.privateCloudVision = privateCloudVision
        self.reason = reason
    }

    /// A meal photo can be recognized.
    public var photos: Bool { MealEngines.engine(photo: true, in: self) != nil }
    /// A typed or dictated description can be recognized.
    public var descriptions: Bool { MealEngines.engine(photo: false, in: self) != nil }

    /// The app has Apple's entitlement for Private Cloud Compute (`PrivateCloud`). Without it the
    /// cloud is never offered, since a request would stop the app; Settings hides the switch.
    public static var privateCloudEntitled: Bool { PrivateCloud.isEntitled }

    /// Safe to call on any OS version: before iOS 27 nothing is available.
    public static func current(allowCloud: Bool) -> MealAIAvailability {
        if #available(iOS 27.0, macOS 27.0, *) { return MealEngines.availability(allowCloud: allowCloud) }
        return MealAIAvailability(
            onDevice: false, onDeviceVision: false, privateCloud: false,
            reason: "Meal recognition needs iOS 27 with Apple Intelligence.")
    }
}

/// Which model answers what. Pure decisions over an availability snapshot, so they are tested
/// without a model.
enum MealEngines {
    /// On device when it can (with vision for photos), else Private Cloud Compute when allowed.
    static func engine(photo: Bool, in state: MealAIAvailability) -> MealEngine? {
        if state.onDevice && (!photo || state.onDeviceVision) { return .onDevice }
        if state.privateCloud && (!photo || state.privateCloudVision) { return .privateCloud }
        return nil
    }

    /// What to try after `engine` failed with `error`: the other engine when it can do the same
    /// job, or for a photo the on-device model reading only the person's note. Nil to give up.
    static func fallback(
        after error: MealAIError, from engine: MealEngine, photo: Bool, hasNote: Bool,
        in state: MealAIAvailability
    ) -> (engine: MealEngine, photo: Bool)? {
        switch engine {
        case .privateCloud:
            // The device model may still answer what the cloud couldn't: a description, or a photo's note.
            switch error {
            case .network, .quotaReached, .unavailable, .busy, .failed: break
            default: return nil
            }
            guard state.onDevice else { return nil }
            if photo && state.onDeviceVision { return (.onDevice, true) }
            return !photo || hasNote ? (.onDevice, false) : nil
        case .onDevice:
            // A longer context, a model that's ready, or a free one after the device stayed busy.
            switch error {
            case .tooLong, .busy, .unavailable, .failed: break
            default: return nil
            }
            guard state.privateCloud && (!photo || state.privateCloudVision) else { return nil }
            return (.privateCloud, photo)
        }
    }

    @available(iOS 27.0, macOS 27.0, *)
    static func availability(
        allowCloud: Bool, entitled: Bool = PrivateCloud.isEntitled, cloud probe: () -> (available: Bool, vision: Bool) = probeCloud
    ) -> MealAIAvailability {
        let model = SystemLanguageModel.default
        var device = false
        var deviceReason: String?
        switch model.availability {
        case .available:
            device = true
        case .unavailable(.deviceNotEligible):
            deviceReason = "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            deviceReason = "Turn on Apple Intelligence in Settings to log meals from photos and descriptions."
        case .unavailable(.modelNotReady):
            deviceReason = "Apple Intelligence is still getting ready. Try again later."
        case .unavailable:
            deviceReason = "Apple Intelligence isn't available right now."
        }
        let vision = device && model.capabilities.contains(.vision)
        var cloud = false
        var cloudVision = false
        // Not even asked without the entitlement: a request to it would stop the app.
        if allowCloud && entitled {
            (cloud, cloudVision) = probe()
        }
        var state = MealAIAvailability(
            onDevice: device, onDeviceVision: vision, privateCloud: cloud, privateCloudVision: cloudVision,
            reason: nil)
        state.reason = reason(state, deviceReason: deviceReason, allowCloud: allowCloud, entitled: entitled)
        return state
    }

    /// Whether Private Cloud Compute can answer now, and read photos.
    @available(iOS 27.0, macOS 27.0, *)
    static func probeCloud() -> (available: Bool, vision: Bool) {
        let pcc = PrivateCloudComputeLanguageModel()
        let available = pcc.isAvailable && !pcc.quotaUsage.isLimitReached
        return (available, available && pcc.capabilities.contains(.vision))
    }

    /// What to tell the person when photos or descriptions can't be read. Offers the Private Cloud
    /// Compute switch only when the app can use it.
    static func reason(_ state: MealAIAvailability, deviceReason: String?, allowCloud: Bool, entitled: Bool) -> String? {
        if !state.descriptions { return deviceReason ?? "Apple Intelligence isn't available right now." }
        guard !state.photos else { return nil }
        return allowCloud || !entitled
            ? "Photo recognition isn't available on this device right now. Describe the meal instead."
            : "This device's model can't read photos. Allow Private Cloud Compute to log meals from photos."
    }
}
