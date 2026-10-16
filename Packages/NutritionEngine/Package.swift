// swift-tools-version: 6.2
import PackageDescription

/// Macro Track's engine: the weight trend, maintenance estimated from intake and weigh-ins, the
/// assessment, phase planning, adaptive targets and the analysis behind every "do this next".
/// Pure Swift over SystemCore, so `swift test` runs it on a Mac.
let package = Package(
    name: "NutritionEngine",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [.library(name: "NutritionEngine", targets: ["NutritionEngine"])],
    dependencies: [.package(path: "../SystemCore")],
    targets: [
        .target(name: "NutritionEngine", dependencies: ["SystemCore"]),
        .testTarget(name: "NutritionEngineTests", dependencies: ["NutritionEngine"]),
    ],
    swiftLanguageModes: [.v6]
)
