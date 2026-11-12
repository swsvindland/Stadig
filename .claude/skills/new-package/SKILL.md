---
name: new-package
description: Add a new local Swift package to the repo (for a new engine, or splitting one up) and wire it into the apps, the generator, the scripts and CI. Use when creating a package under Packages/ or making an app depend on another package.
---

# Add a package

1. **Create it** at `Packages/<Name>/` in the shape the others use:

   ```swift
   // swift-tools-version: 6.2
   import PackageDescription

   /// One paragraph: what this package owns and what it deliberately doesn't.
   let package = Package(
       name: "<Name>",
       platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26), .visionOS(.v26)],
       products: [.library(name: "<Name>", targets: ["<Name>"])],
       dependencies: [.package(path: "../SystemCore")],
       targets: [
           .target(name: "<Name>", dependencies: ["SystemCore"]),
           .testTarget(name: "<Name>Tests", dependencies: ["<Name>"]),
       ],
       swiftLanguageModes: [.v6]
   )
   ```

   macOS is in the platforms so `swift test` runs on the Mac. Pure logic: Foundation and the package's own dependencies only; anything needing UIKit, HealthKit or the camera stays in an app or `HealthBridge`. No third-party dependencies.

2. **Tests** in `Tests/<Name>Tests/` with Swift Testing, from the first commit.

3. **Wire it in:**
   - `Scripts/generate-project.py`: add it to the app's package list (`LIFT_PACKAGES`, `MACRO_PACKAGES`) and to the products of each target that imports it; run the generator.
   - `Scripts/build.sh` finds every package by itself (`PACKAGES` is a glob); nothing to change.
   - `docs/ci-cd.md`: add `Packages/<Name>` to the Xcode Cloud file filter of every app that uses it, and tell the owner to update those workflows (they live in App Store Connect).
   - GitHub's `CI` picks it up through `Scripts/build.sh test`; nothing to change there.

4. **Document it**: a line in the README's layout, and the app doc section that uses it.

5. `Scripts/build.sh test <Name>`, then build each app that links it.
