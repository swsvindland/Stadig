// swift-tools-version: 6.2
import PackageDescription

/// The hub's engine: what a work or school schedule looks like, reading one from a sentence, and a day
/// and a week put together from what the apps published. The rules every app must agree on live in
/// SystemCore; this is only what the hub needs to show them. Pure Swift, so `swift test` runs it on a Mac.
let package = Package(
    name: "HubEngine",
    platforms: [.iOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [.library(name: "HubEngine", targets: ["HubEngine"])],
    dependencies: [.package(path: "../SystemCore"), .package(path: "../SystemStore")],
    targets: [
        .target(name: "HubEngine", dependencies: ["SystemCore", "SystemStore"]),
        .testTarget(name: "HubEngineTests", dependencies: ["HubEngine", "SystemCore", "SystemStore"]),
    ],
    swiftLanguageModes: [.v6]
)
