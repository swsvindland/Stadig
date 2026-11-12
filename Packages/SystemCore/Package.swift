// swift-tools-version: 6.2
import PackageDescription

/// The System's shared core: the models both apps agree on, and every piece of logic whose answer
/// must be identical wherever it runs (strength scoring, the Fatigue Budget, RPE trust calibration,
/// progression, the block and deload scheduler, life modes, discipline, the stats board). Pure Swift,
/// Foundation only, so `swift test` runs it on a Mac.
let package = Package(
    name: "SystemCore",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [.library(name: "SystemCore", targets: ["SystemCore"])],
    targets: [
        .target(name: "SystemCore"),
        .testTarget(name: "SystemCoreTests", dependencies: ["SystemCore"]),
    ],
    swiftLanguageModes: [.v6]
)
