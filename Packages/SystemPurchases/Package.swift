// swift-tools-version: 6.2
import PackageDescription

/// How each app is paid for, the same way everywhere: 21 free days with nothing to sign up for, then
/// a one-time purchase or a monthly subscription, with one more day on offer for anyone not ready
/// (`Access`); the App Store's side of it (`Purchases`); and the one paywall they all show
/// (`PaywallView`). Each app brings its products and its pitch (`PurchaseConfiguration`). StoreKit and
/// SwiftUI live here rather than in the apps because three copies of this would be three chances to
/// disagree about money, and the fine print Apple requires has to be right in all of them.
let package = Package(
    name: "SystemPurchases",
    platforms: [.iOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [.library(name: "SystemPurchases", targets: ["SystemPurchases"])],
    dependencies: [.package(path: "../SystemCore"), .package(path: "../SystemStore")],
    targets: [
        .target(name: "SystemPurchases", dependencies: ["SystemCore", "SystemStore"]),
        .testTarget(name: "SystemPurchasesTests", dependencies: ["SystemPurchases", "SystemCore", "SystemStore"]),
    ],
    swiftLanguageModes: [.v6]
)
