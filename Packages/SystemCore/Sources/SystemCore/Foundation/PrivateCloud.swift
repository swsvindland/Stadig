import Foundation

/// Whether an app may send work to Private Cloud Compute. It needs Apple's managed entitlement
/// (com.apple.developer.private-cloud-compute): without it, Foundation Models still reports Private
/// Cloud Compute as available, then stops the app on the first request with a fatal error that can't
/// be caught. So an app uses it only when its Info.plist says it has the entitlement, by setting
/// `SystemAIPrivateCloud` to true. Until then, everything runs on the device.
public enum PrivateCloud {
    /// The Info.plist key an app sets to true once Apple has granted it the entitlement.
    public static let infoKey = "SystemAIPrivateCloud"

    /// This app has declared the entitlement.
    public static var isEntitled: Bool { isEntitled(Bundle.main.infoDictionary) }

    static func isEntitled(_ info: [String: Any]?) -> Bool { info?[infoKey] as? Bool ?? false }
}
