// swift-tools-version: 6.2
import PackageDescription

/// Every exercise, tagged with movement pattern, muscles, joints loaded, systemic and local fatigue
/// cost, failure safety tier and default rest. Drives substitutions, injury filtering and the
/// Fatigue Budget's choices.
let package = Package(
    name: "ExerciseLibrary",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [.library(name: "ExerciseLibrary", targets: ["ExerciseLibrary"])],
    dependencies: [.package(path: "../SystemCore")],
    targets: [
        .target(name: "ExerciseLibrary", dependencies: ["SystemCore"], resources: [.process("Resources")]),
        .testTarget(name: "ExerciseLibraryTests", dependencies: ["ExerciseLibrary"]),
    ],
    swiftLanguageModes: [.v6]
)
