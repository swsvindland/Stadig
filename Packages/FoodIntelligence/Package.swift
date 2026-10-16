// swift-tools-version: 6.2
import PackageDescription

/// Photo, description and label logging with Apple's models: on device first, Private Cloud
/// Compute when allowed. The model names foods and amounts; nutrients always come from the catalog.
let package = Package(
    name: "FoodIntelligence",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "FoodIntelligence", targets: ["FoodIntelligence"])],
    dependencies: [.package(path: "../SystemCore"), .package(path: "../FoodDatabase")],
    targets: [
        .target(name: "FoodIntelligence", dependencies: ["SystemCore", "FoodDatabase"]),
        .testTarget(name: "FoodIntelligenceTests", dependencies: ["FoodIntelligence", "FoodDatabase", "SystemCore"]),
    ],
    swiftLanguageModes: [.v6]
)
