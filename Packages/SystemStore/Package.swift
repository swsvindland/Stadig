// swift-tools-version: 6.2
import PackageDescription

/// Each app's own CloudKit-synced database (one SwiftData model holding versioned JSON records), the
/// shared App Group container the apps publish small summaries through for each other, and the
/// portable exports: a full backup file and CSV. Depends only on SystemCore and Apple frameworks.
let package = Package(
    name: "SystemStore",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [.library(name: "SystemStore", targets: ["SystemStore"])],
    dependencies: [.package(path: "../SystemCore")],
    targets: [
        .target(name: "SystemStore", dependencies: ["SystemCore"]),
        .testTarget(name: "SystemStoreTests", dependencies: ["SystemStore", "SystemCore"]),
    ],
    swiftLanguageModes: [.v6]
)
