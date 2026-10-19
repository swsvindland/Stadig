// swift-tools-version: 6.2
import PackageDescription

/// Lift Track's own engine: gyms and loads, the assessment block, the program generator with its
/// elastic time budget, session planning, the live session, and the analysis behind every
/// "do this next". Pure Swift over SystemCore and ExerciseLibrary, shared by iPhone and Watch.
let package = Package(
    name: "LiftEngine",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [.library(name: "LiftEngine", targets: ["LiftEngine"])],
    dependencies: [.package(path: "../SystemCore"), .package(path: "../ExerciseLibrary")],
    targets: [
        .target(name: "LiftEngine", dependencies: ["SystemCore", "ExerciseLibrary"]),
        // Fixtures: sessions as an earlier version saved them, which every later one must still read.
        .testTarget(name: "LiftEngineTests", dependencies: ["LiftEngine"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
