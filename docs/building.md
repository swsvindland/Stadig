# Building and running

You need Xcode 27 (its Swift 6.4 toolchain includes `swift-format`) and nothing else: there are no third-party dependencies, in the apps or the packages.

## Getting started

```sh
Scripts/fetch-catalogs.sh           # once: download the catalogs Stadig Macro bundles (needs gh signed in)
Scripts/build.sh test               # every package's tests
open Apps/LiftTrack/LiftTrack.xcodeproj
```

Each app's scheme builds and runs it on whichever device you pick (an iPhone or iPad, My Mac, Apple Vision Pro); `LiftTrack` and `MacroTrack` also build their widgets and the embedded Watch app, and `LiftTrackWatch` and `MacroTrackWatch` build the Watch apps alone. In Xcode, ⌘U runs the scheme's default test plan (unit and integration); pick the `…UI` plan for the UI tests.

The catalogs are optional. Without them Stadig Macro still works, with the USDA catalog that is in git, and supplements are added from a photo of the label or typed in. Building them from source instead of downloading them: [Apps/MacroTrack/Catalogs/README.md](../Apps/MacroTrack/Catalogs/README.md).

To see an app with data in it, launch a DEBUG build with `-inMemoryStore -seedSampleData`. Each app's doc lists the rest of its launch arguments ([Stadig Lift](lift.md), [Stadig Macro](macro.md)).

## Without a developer account

`Scripts/build.sh` builds for the simulators, and for this Mac signed ad hoc, so none of that needs an Apple developer account. An ad hoc Mac build has no iCloud or App Group: the app keeps its data on that Mac, and Settings says "This device only".

The Xcode projects are signed for the author's team (`TEAM` in `Scripts/generate-project.py`), and the bundle ids, iCloud containers and App Group ([architecture.md](architecture.md#identifiers)) belong to it. For a build on your own devices, set your team and your own identifiers there, in the entitlements under `Apps/<App>/Config` and where the code names them (`git grep dev.svindland`), then run the generator.

## Everyday commands

```sh
Scripts/build.sh lint               # swift-format, strict: what CI checks
Scripts/build.sh format             # fix formatting in place
Scripts/build.sh test [Package]     # package tests (all, or one)
Scripts/build.sh unit lift [ipad|vision|mac]   # an app's unit and integration tests (lift or macro)
Scripts/build.sh ui lift [ipad|vision]         # an app's UI tests
ONLY=LaunchAndOnboardingUITests Scripts/build.sh ui lift   # one class of them
Scripts/build.sh ios|watch|macro|macro-watch   # build one app for the iOS simulator (or a Watch app)
Scripts/build.sh mac|vision lift    # build an app for the Mac (it runs on this Mac) or Vision Pro
Scripts/build.sh all                # lint, every package's tests, every app build
Scripts/leaks.sh lift               # after building an app: run `leaks` on its seeded screens
Scripts/store-screenshots.sh lift   # recapture an app's App Store screenshots into Store/ (then storeassets; Store/README.md)
python3 Scripts/generate-project.py # rewrite the Xcode projects, schemes and test plans after changing the generator
swift Scripts/make-icons.swift      # redraw Stadig Lift's icons (make-macro-icons for Stadig Macro's)
python3 Scripts/build-catalogs.py update|build|validate   # Stadig Macro's catalogs: what's newer upstream, rebuild, check calories against macros
Scripts/publish-catalogs.sh         # after rebuilding a catalog: upload them all as a new release, then commit the manifest
```

Builds print only errors and warnings, into a DerivedData folder of the checkout's own, and simulator work runs on simulators of the checkout's own ("Stadig Tests", "Stadig iPad" and "Stadig Vision"), created the first time. The header of `Scripts/build.sh` has every command and option.

## The Xcode projects are generated

`Scripts/generate-project.py` writes each app's `.xcodeproj`, schemes and test plans, and CI fails if they differ from what it writes. Don't edit them by hand.

New Swift files in an app's folders need no project change: the targets use synchronized folders. Only new targets, packages, build settings or Info.plist keys go through the generator.

## Quality bar

- **Formatting and lint:** `swift-format` with the repo's `.swift-format` (4 spaces, 150 columns); CI fails on any finding.
- **Zero warnings:** CI builds packages and apps with warnings as errors (`STRICT=1`).
- **Swift 6 language mode** with strict concurrency everywhere; the app targets default to the main actor.
- **Tests at every layer:** [testing.md](testing.md), and what the package tests cover in [package-tests.md](package-tests.md).
- **CI/CD:** every push is checked; `main` ships to TestFlight; release branches ship to the App Store. [ci-cd.md](ci-cd.md).
