// swift-tools-version: 6.2
import PackageDescription

/// Mind Track's engine: Lift Track for the mind. Spaced repetition, the weekly split across
/// domains, the assessment that finds a level in each, mastery-gated progression, review weeks,
/// and the honest tests behind Intelligence and Wisdom. Japanese words and sentences come from
/// the bundled catalog; maths problems are generated; grammar items and the reading ladder ship as
/// resources. Pure Swift over SystemCore (plus SQLite for the catalog), so `swift test` runs it on a Mac.
let package = Package(
    name: "MindEngine",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [.library(name: "MindEngine", targets: ["MindEngine"])],
    dependencies: [.package(path: "../SystemCore")],
    targets: [
        .target(name: "MindEngine", dependencies: ["SystemCore"], resources: [.process("Resources")]),
        .testTarget(name: "MindEngineTests", dependencies: ["MindEngine"]),
    ],
    swiftLanguageModes: [.v6]
)
