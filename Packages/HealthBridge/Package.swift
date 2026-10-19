// swift-tools-version: 6.2
import PackageDescription

/// HealthKit read/write for every app in the family: workouts, body measurements, heart rate, sleep,
/// HRV, resting heart rate, VO2 max, and the Watch's live workout session.
let package = Package(
    name: "HealthBridge",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [.library(name: "HealthBridge", targets: ["HealthBridge"])],
    dependencies: [.package(path: "../SystemCore")],
    targets: [
        .target(name: "HealthBridge", dependencies: ["SystemCore"]),
        .testTarget(name: "HealthBridgeTests", dependencies: ["HealthBridge", "SystemCore"]),
    ],
    swiftLanguageModes: [.v6]
)
