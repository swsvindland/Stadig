# Stadig: Stadig Lift and Stadig Macro

**Stadig** (STAH-dig, Norwegian for steady; "the System" in the design doc and the code) is a small family of fast, offline-first fitness apps, Stadig Lift and Stadig Macro. The apps don't just chart trends. They tell you what to do next, and every insight ends in a concrete action.

- **Stadig Lift** is the training app: every session prescribed, and every set adjusted to how it went. On the iPad and the Mac it's also where you study the program, the exercise library and your history; an iPad in the gym runs the session in two panes. iPhone, iPad, Mac, Apple Vision Pro and Apple Watch.
- **Stadig Macro** is the nutrition app. It learns your real maintenance from logging and weigh-ins, recommends one phase (cut, bulk, maintenance and the rest) with its reasons, and adapts targets each week. It's built so a visit can be a glance and a tap: search, scan, a photo or a sentence, with Apple's on-device model and Private Cloud Compute doing the reading. Turned on, it reads meal timing from the log (the gaps between meals, the overnight fast) and runs fasts toward a goal, with their phases on the Lock Screen and the Watch. On the iPad and the Mac it adds a food table to search and compare, the meal plan as a week, and a history of every day; the Watch logs from the wrist. iPhone, iPad, Mac, Apple Vision Pro and Apple Watch.

This repo is built from the design doc ("The System — Hub Design", Oct 15, 2026), which is the source of truth: one repo, with the apps as thin shells over shared local Swift packages. Each app is one native target for every device it runs on. Both apps are free and open source: purchases are switched off (`enabled: false` in each app's `Purchase/Purchases.swift`), and [docs/app-store-connect.md](docs/app-store-connect.md) says what's left to change on the store's side. The look is in [docs/design.md](docs/design.md). No third-party dependencies.

## Layout

```
Packages/             Local Swift packages: all the logic, each with its own tests
  SystemCore/         Shared models and every rule that must give the same answer everywhere, the stats both
                      apps show (StatsBoard) among them
  ExerciseLibrary/    332 tagged exercises, substitutions, injury filtering, drills
  SystemStore/        Each app's CloudKit-synced database, the shared App Group container (and FamilySync, which
                      carries it to the person's other devices), backups, CSV
  SystemPurchases/    How each app was paid for (free days, StoreKit, the paywall); switched off, both apps are free
  HealthBridge/       HealthKit read/write, and the Watch's live workout session
  LiftEngine/         Stadig Lift's engine: gyms, generator, assessment, session planner, live session, analysis
  NutritionEngine/    Stadig Macro's engine: weight trend, maintenance, assessment, phase planner, check-ins, targets
  FoodDatabase/       The offline food catalogs (USDA, Open Food Facts), search, portions, barcodes, label parsing,
                      and the NIH supplement label catalog with its Supplement Facts parser
  FoodIntelligence/   Meal photos, descriptions and label photos through Apple's models; nutrients from the catalog
  MealPlanner/        A week of prep-friendly meals sized to the targets, the grocery list and a timed prep day
Apps/<App>/           LiftTrack, MacroTrack: thin SwiftUI shells over the packages
  iOS/                The app for iPhone, iPad, the Mac and Vision Pro (one multiplatform target), one folder
                      per feature; Platform/Adaptive.swift spells what differs between platforms
  Tests/              The app's unit and integration tests (Swift Testing, hosted in the app)
  UITests/            UI tests of first run, the offer and the tabs, and the store screenshots
  Widgets/, Shared/   Widgets and Live Activities, and the snapshot they share with the app
  Watch/, WatchWidgets/   Stadig Lift's and Stadig Macro's Watch apps and their complications
  Records/            Stadig Macro's records that its iPhone and Watch apps both compile
  Catalogs/           Stadig Macro's bundled catalogs (not in git; see the README there)
  Config/             Info plists and entitlements (the Mac's in <App>-macOS.entitlements)
  ci_scripts/         What Xcode Cloud runs around each build (one line each, calling Scripts/xcode-cloud.sh)
  <App>.xcodeproj, <App>.xctestplan, <App>UI.xctestplan   Written by Scripts/generate-project.py: don't edit
Scripts/              build.sh (build, lint, test), generate-project.py, xcode-cloud.sh, the catalog builders
                      and fetch/publish scripts, the icon drawers
docs/                 How each app maps to the design doc, testing, CI/CD, decisions to check, what's verified
Site/                 stadig.dev, the marketing site (Astro; its own README)
Store/                The App Store screenshots: a storeassets project per app and Watch app (its own README)
.github/workflows/    GitHub Actions: lint and package tests on every push, the site build
```

The apps talk to each other through the shared container, which reaches the person's other devices through the family iCloud container (so Stadig Macro on the iPad sees what Stadig Lift wrote on the iPhone): Stadig Macro publishes the nutrition phase and day-by-day logging, and Stadig Lift publishes its training calendar, measurements and strength. Each publishes its stats, which either app can read merged with the other's. [docs/shared-container.md](docs/shared-container.md) has the contract, and what the hub app and Stadig Mind, which both left this repo, wrote that may still be on devices.

## Getting started

You need Xcode 27 (its Swift 6.4 toolchain includes `swift-format`), nothing else: there are no third-party dependencies.

```sh
Scripts/fetch-catalogs.sh           # once: download the catalogs Stadig Macro bundles (needs gh signed in)
Scripts/build.sh test               # every package's tests
open Apps/LiftTrack/LiftTrack.xcodeproj
```

Each app's scheme builds and runs it on whichever device you pick (an iPhone or iPad, My Mac, Apple Vision Pro); `LiftTrack` and `MacroTrack` also build their widgets and the embedded Watch app, and `LiftTrackWatch` and `MacroTrackWatch` build the Watch apps alone. In Xcode, ⌘U runs the scheme's default test plan (unit and integration); pick the `…UI` plan for the UI tests.

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
python3 Scripts/popular-brands.py Apps/MacroTrack/Catalogs/off.db   # after rebuilding off.db: the brands search suggests, most scanned first
```

New Swift files in an app's folders need no project change: the targets use synchronized folders. Only new targets, packages, build settings or Info.plist keys go through `Scripts/generate-project.py`.

Building the catalogs from source instead of downloading them: `Apps/MacroTrack/Catalogs/README.md`.

## Quality bar

- **Formatting and lint:** `swift-format` with the repo's `.swift-format`; CI fails on any finding. Claude Code formats each Swift file it edits.
- **Zero warnings:** CI builds packages and apps with warnings as errors.
- **Swift 6 language mode** with strict concurrency everywhere; the app targets default to the main actor.
- **Tests at every layer:** see [docs/testing.md](docs/testing.md).
- **CI/CD:** every push is checked; `main` ships to TestFlight; release branches ship to the App Store. See [docs/ci-cd.md](docs/ci-cd.md).

## Docs

- [Stadig Lift](docs/lift-track.md), [Stadig Macro](docs/macro-track.md): how the design doc maps to the code, and each app's DEBUG launch arguments
- [The shared container](docs/shared-container.md): what the apps publish for each other, what the hub and Stadig Mind left behind, and the stats
- [Testing](docs/testing.md) and [what the package tests cover](docs/package-tests.md)
- [CI/CD](docs/ci-cd.md): GitHub Actions, Xcode Cloud workflows, branches and releases
- [Decisions to check](docs/decisions.md): product calls made without sign-off, and what isn't built yet
- [Verified, and not yet](docs/verification.md)
- [CLAUDE.md](CLAUDE.md): working rules for Claude Code sessions (and a good checklist for people)

## Identifiers

**Signing:** the generator sets `DEVELOPMENT_TEAM` to `9HAG9PT8LJ` for every target. Identifiers:

| | Stadig Lift | Stadig Macro |
|---|---|---|
| Bundle ids | `dev.svindland.stadig.lift` (`.widgets`, `.watchkitapp`, `.watchkitapp.widgets`) | `dev.svindland.stadig.macro` (`.widgets`, `.watchkitapp`, `.watchkitapp.widgets`) |
| iCloud containers | `iCloud.dev.svindland.stadig.lift`, and the family's `iCloud.dev.svindland.stadig` | `iCloud.dev.svindland.stadig.macro`, and the family's |
| App Group | `group.dev.svindland.stadig`, shared by the whole family | same |
| In-app purchases (off) | `dev.svindland.stadig.lift.unlock` (non-consumable), `dev.svindland.stadig.lift.monthly` (subscription) | `dev.svindland.stadig.macro.unlock` (non-consumable), `dev.svindland.stadig.macro.monthly` (subscription) |
| URL scheme | `lifttrack://start` | `macrotrack://log`, `scan`, `camera`, `describe`, `quickadd`, `weigh`, `plan`, `supplements` |

Each bundle id covers the iPhone, iPad, Mac and Vision Pro builds. The ids moved under `dev.svindland.stadig` on 2026-10-18, before anything reached App Store Connect. Before that they were `dev.svindland.lifttrack`, `macrotrack` and `group.dev.svindland.system`. Health still treats samples from the old ids as the app's own (`AppModel.ownBundlePrefixes`).
