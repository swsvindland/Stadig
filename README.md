# The System: Lift Track, Macro Track and Mind Track

**The System** is a small family of fast, offline-first apps (Lift Track, Macro Track and Mind Track) with an optional hub on top. The apps don't just chart trends. They tell you what to do next, and every insight ends in a concrete action.

- **Lift Track** is the training app: every session prescribed, and every set adjusted to how it went. iPhone, iPad and Apple Watch.
- **Macro Track** is the nutrition app. It learns your real maintenance from logging and weigh-ins, recommends one phase (cut, bulk, maintenance and the rest) with its reasons, and adapts targets each week. It's built so a visit can be a glance and a tap: search, scan, a photo or a sentence, with Apple's on-device model and Private Cloud Compute doing the reading.
- **Mind Track** is the doc's Knowledge app, "Lift Track for the mind": focused 25-minute sessions in Japanese, maths, writing and reading. Two weeks find a level in each, subjects rotate across the week like a training split, spaced repetition brings things back just before they'd be forgotten, and something new comes only once the last thing has stuck. Intelligence and Wisdom move only on check-in tests and finished books. iPhone and iPad (and the Mac, as the iPad app).

This repo is built from the System hub design doc ("The System — Hub Design", Oct 15, 2026), which is the source of truth: one repo, with the apps as thin shells over shared local Swift packages. One-time purchases, no subscriptions, and no third-party dependencies.

## Layout

```
Packages/             Local Swift packages: all the logic, each with its own tests
  SystemCore/         Shared models and every rule that must give the same answer everywhere
  ExerciseLibrary/    332 tagged exercises, substitutions, injury filtering, drills
  SystemStore/        Each app's CloudKit-synced database, the shared App Group container, backups, CSV
  HealthBridge/       HealthKit read/write, and the Watch's live workout session
  LiftEngine/         Lift Track's engine: gyms, generator, assessment, session planner, live session, analysis
  NutritionEngine/    Macro Track's engine: weight trend, maintenance, assessment, phase planner, check-ins, targets
  FoodDatabase/       The offline food catalogs (USDA, Open Food Facts), search, portions, barcodes, label parsing,
                      and the NIH supplement label catalog with its Supplement Facts parser
  FoodIntelligence/   Meal photos, descriptions and label photos through Apple's models; nutrients from the catalog
  MealPlanner/        A week of prep-friendly meals sized to the targets, the grocery list and a timed prep day
  MindEngine/         Mind Track's engine: spaced repetition, courses and the split, language packs, one module and
                      part runner per subject, the maths skill graph, the writing bank, the reading ladder, analysis
  SystemAI/           The one interface to a language model: Apple's on-device model first, Private Cloud Compute
                      for heavier jobs when allowed, a plain reason when neither can answer
Apps/<App>/           LiftTrack, MacroTrack, MindTrack: thin SwiftUI shells over the packages
  iOS/                The iPhone/iPad app, one folder per feature
  Tests/              The app's unit and integration tests (Swift Testing, hosted in the app)
  UITests/            The app's end-to-end UI tests
  Widgets/, Shared/   Widgets and Live Activities, and the snapshot they share with the app
  Watch/, WatchWidgets/   Lift Track's Watch app and its complication
  Catalogs/           Macro Track's and Mind Track's bundled catalogs (not in git; see the README there)
  Config/             Info plists and entitlements
  ci_scripts/         What Xcode Cloud runs around each build (one line each, calling Scripts/xcode-cloud.sh)
  <App>.xcodeproj, <App>.xctestplan, <App>UI.xctestplan   Written by Scripts/generate-project.py: don't edit
Scripts/              build.sh (build, lint, test), generate-project.py, xcode-cloud.sh, the catalog builders
                      and fetch/publish scripts, the icon drawers
docs/                 How each app maps to the design doc, testing, CI/CD, decisions to check, what's verified
Site/                 stadig.dev, the marketing site (Astro; its own README)
.github/workflows/    GitHub Actions: lint and package tests on every push, the site build
```

The **hub** doesn't exist yet. The apps already publish everything the hub needs and read what it would write. Lift Track and Macro Track talk to each other today through the shared container: Macro Track publishes the nutrition phase and day-by-day logging, and Lift Track publishes its training calendar, measurements and strength. Mind Track reads that calendar (Lift Track's deloads are its review weeks) and the shared life modes, and publishes its Intelligence and Wisdom readings, study sessions, Discipline and the study the hub could fit into a free evening.

## Getting started

You need Xcode 27 (its Swift 6.4 toolchain includes `swift-format`), nothing else: there are no third-party dependencies.

```sh
Scripts/fetch-catalogs.sh           # once: download the catalogs Macro Track and Mind Track bundle (needs gh signed in)
Scripts/build.sh test               # every package's tests
open Apps/LiftTrack/LiftTrack.xcodeproj
```

Each app's scheme builds and runs it; `LiftTrack` also builds the widgets and the embedded Watch app, and `LiftTrackWatch` builds the Watch app alone. In Xcode, ⌘U runs the scheme's default test plan (unit and integration); pick the `…UI` plan for the UI tests.

## Everyday commands

```sh
Scripts/build.sh lint               # swift-format, strict: what CI checks
Scripts/build.sh format             # fix formatting in place
Scripts/build.sh test [Package]     # package tests (all, or one)
Scripts/build.sh unit lift          # an app's unit and integration tests (lift, macro, mind)
Scripts/build.sh ui lift            # an app's UI tests
Scripts/build.sh ios|watch|macro|mind   # build one app
Scripts/build.sh all                # lint, every package's tests, every app build
Scripts/leaks.sh lift               # after building an app: run `leaks` on its seeded screens
python3 Scripts/generate-project.py # rewrite the Xcode projects, schemes and test plans after changing the generator
swift Scripts/make-icons.swift      # redraw Lift Track's icons (make-macro-icons, make-mind-icons for the others)
Scripts/publish-catalogs.sh         # after rebuilding a catalog: upload them all as a new release, then commit the manifest
```

New Swift files in an app's folders need no project change: the targets use synchronized folders. Only new targets, packages, build settings or Info.plist keys go through `Scripts/generate-project.py`.

Building the catalogs from source instead of downloading them: `Apps/MacroTrack/Catalogs/README.md` and `Apps/MindTrack/Catalogs/README.md`.

## Quality bar

- **Formatting and lint:** `swift-format` with the repo's `.swift-format`; CI fails on any finding. Claude Code formats each Swift file it edits.
- **Zero warnings:** CI builds packages and apps with warnings as errors.
- **Swift 6 language mode** with strict concurrency everywhere; the app targets default to the main actor.
- **Tests at every layer:** see [docs/testing.md](docs/testing.md).
- **CI/CD:** every push is checked; `main` ships to TestFlight; release branches ship to the App Store. See [docs/ci-cd.md](docs/ci-cd.md).

## Docs

- [Lift Track](docs/lift-track.md), [Macro Track](docs/macro-track.md), [Mind Track](docs/mind-track.md): how the design doc maps to the code, and each app's DEBUG launch arguments
- [Testing](docs/testing.md) and [what the package tests cover](docs/package-tests.md)
- [CI/CD](docs/ci-cd.md): GitHub Actions, Xcode Cloud workflows, branches and releases
- [Decisions to check](docs/decisions.md): product calls made without sign-off, and what isn't built yet
- [Verified, and not yet](docs/verification.md)
- [CLAUDE.md](CLAUDE.md): working rules for Claude Code sessions (and a good checklist for people)

## Identifiers

**Signing:** the generator sets `DEVELOPMENT_TEAM` to `9HAG9PT8LJ` for every target. Identifiers:

| | Lift Track | Macro Track |
|---|---|---|
| Bundle ids | `dev.svindland.stadig.lift` (`.widgets`, `.watchkitapp`, `.watchkitapp.widgets`) | `dev.svindland.stadig.macro` (`.widgets`) |
| iCloud container | `iCloud.dev.svindland.stadig.lift` | `iCloud.dev.svindland.stadig.macro` |
| App Group | `group.dev.svindland.stadig`, shared by the whole family | same |
| In-app purchase | `dev.svindland.stadig.lift.unlock` (non-consumable) | `dev.svindland.stadig.macro.unlock` (non-consumable) |
| URL scheme | `lifttrack://start` | `macrotrack://log`, `scan`, `camera`, `describe`, `quickadd`, `weigh`, `plan`, `supplements` |

Mind Track is `dev.svindland.stadig.mind`, with `iCloud.dev.svindland.stadig.mind` and `dev.svindland.stadig.mind.unlock`. The ids moved under `dev.svindland.stadig` on 2026-10-18, before anything reached App Store Connect. Before that they were `dev.svindland.lifttrack`, `macrotrack`, `mindtrack` and `group.dev.svindland.system`. Health still treats samples from the old ids as the app's own (`AppModel.ownBundlePrefixes`).
