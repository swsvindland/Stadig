// swift-tools-version: 6.2
import PackageDescription

/// The one way the apps reach a language model: Apple's on-device model first, Private Cloud
/// Compute for heavier jobs when allowed, and a clear reason when neither can answer. Core logic
/// never depends on it. Another provider could sit behind the same interface later.
let package = Package(
    name: "SystemAI",
    platforms: [.iOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [.library(name: "SystemAI", targets: ["SystemAI"])],
    dependencies: [.package(path: "../SystemCore")],
    targets: [
        .target(name: "SystemAI", dependencies: ["SystemCore"]),
        .testTarget(name: "SystemAITests", dependencies: ["SystemAI"]),
    ],
    swiftLanguageModes: [.v6]
)
