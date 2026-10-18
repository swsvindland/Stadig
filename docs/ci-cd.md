# CI/CD

Two systems share the work. **GitHub Actions** checks every push cheaply: formatting, the generated projects, and every package's tests. **Xcode Cloud** builds, tests and ships the apps: it runs each app's test plans and its packages' tests, archives, and sends builds to TestFlight. GitHub's macOS minutes bill at ten times Linux ones on a private repo, so the app builds live in Xcode Cloud's monthly hours instead.

## What runs when

| Push to | GitHub Actions (`CI`) | Xcode Cloud, per app the push touches |
|---|---|---|
| any branch | lint, the generator check, every package's tests with warnings as errors | **Branch** workflow: the app's packages' tests, then its unit and integration test plan |
| `main` | the same | **Main** workflow: packages, unit plan and UI plan, then an archive to TestFlight (internal testers) |
| `release/<app>-<version>` | the same | **Release** workflow: the same tests, then an archive to TestFlight (external testers), ready to submit for review |

Also: on Mondays GitHub runs every package's tests under the thread and address sanitizers, and `CI` can be started by hand with **apps** ticked to build and test all three apps on GitHub (useful when Xcode Cloud's hours run low; about 15 macOS minutes per app, which a private repo on the free plan bills at ten times). `Site` builds the marketing site on pushes that touch `Site/`.

Until the Xcode Cloud workflows below exist, nothing compiles the apps on push: GitHub only lints and runs the package tests. Creating them is the one manual step left.

"Touches" comes from each Xcode Cloud workflow's file filter (below), so a Mind Track change doesn't rebuild Lift Track.

## Branches

- **Work on a branch** named `feature/<topic>` or `fix/<topic>` (Claude Code sessions make `claude/<name>`; all three start Xcode Cloud's Branch workflow). Push as often as you like: GitHub and Xcode Cloud's Branch workflows say whether it's good.
- **`main` is always shippable.** Merge a branch once its checks pass. Every push to `main` puts a fresh internal TestFlight build of each app it touched on your devices (turn on Automatic Updates in TestFlight).
- **Release from a release branch.** When an app is ready for the App Store:
  1. Branch `release/lift-1.1` (or `macro-…`, `mind-…`) from `main`.
  2. On the release branch, set that app's entry in `VERSIONS` in `Scripts/generate-project.py` to the version you're shipping, run it, commit.
  3. On `main`, bump the same entry to the next version (1.2) straight away: TestFlight refuses builds of a version that's already been approved, so `main` must never build a shipped version.
  4. Before the first release only: set `Purchases.enabled` to `true` in the app's `Purchase/Purchases.swift` and check the StoreKit price. A release-branch archive with purchases off fails on purpose (`ci_pre_xcodebuild.sh`), since it would ship the paid app unlocked.
  5. Push the release branch. The Release workflow tests, archives and uploads; submit the build for review in App Store Connect.
  6. Fixes for that release go on the release branch and are merged back to `main`. Tag what shipped (`lift-v1.1`).

Build numbers are Xcode Cloud's: it sets `CFBundleVersion` to its own build number on every archive, so they never collide. The version people see is `VERSIONS` in the generator.

## The checks in detail

- **Lint**: `Scripts/build.sh lint` runs `swift-format lint --strict` with the repo's `.swift-format` (4 spaces, 150 columns, Xcode's own swift-format, so no tool to install). `Scripts/build.sh format` fixes everything it can; Claude Code formats each Swift file it edits (`.claude/settings.json`).
- **Generator check**: CI runs `Scripts/generate-project.py` and fails if the Xcode projects, schemes or test plans differ from what's committed. Change the generator, never the project, and commit what it writes. The generator writes projects exactly as Xcode does, so opening one in Xcode leaves it unchanged.
- **Warnings are errors** on CI: GitHub passes `STRICT=1`, and the generated projects make Debug builds treat warnings as errors whenever the `CI` environment variable is set, which covers Xcode Cloud's Test actions. Local builds and Release archives only warn.
- **Package tests** run with `swift test` on the Mac, and include the catalog tests: CI fetches the catalogs from the release named in `Scripts/catalogs.manifest`. The four tests that run real Vision OCR are skipped on CI's virtual Macs (`NO_VISION_OCR`).
- **App test plans** (`Apps/<App>/<App>.xctestplan` and `<App>UI.xctestplan`, written by the generator) hold the app's own tests: unit and integration tests in `Apps/<App>/Tests`, UI tests in `Apps/<App>/UITests`. See [testing.md](testing.md).

## Setting up Xcode Cloud (once per app)

The repo carries everything Xcode Cloud needs (shared schemes, test plans, `ci_scripts`); the workflows themselves live in App Store Connect. In Xcode: **Report navigator → Cloud → Manage Workflows**, or App Store Connect → the app → **Xcode Cloud**. Create these three for each app.

| | Branch | Main | Release |
|---|---|---|---|
| Start condition | Branch Changes, custom branches beginning with `feature/`, `fix/` and `claude/` (Xcode Cloud can't exclude branches, so name the work branches) | Branch Changes: `main` | Branch Changes: `release/<app>-*` (e.g. `release/lift-*`) |
| Files and folders | the app's folders (below) | the app's folders | the app's folders |
| Auto-cancel builds | on | off | off |
| Environment | latest Xcode 27 release, latest macOS | same | same |
| Actions | Test: scheme `<App>`, test plan `<App>`, iOS, one iPhone simulator | Test `<App>`; Test `<App>UI`; Archive (iOS), TestFlight (Internal Testing Only) | Test `<App>`; Test `<App>UI`; Archive (iOS), TestFlight and App Store |
| Post-actions | none | TestFlight Internal Testing: your internal group | TestFlight External Testing: your beta group |

**The app's folders** (the file filter: start if any file here changes):

- Lift Track: `Apps/LiftTrack`, `Packages/SystemCore`, `Packages/ExerciseLibrary`, `Packages/SystemStore`, `Packages/HealthBridge`, `Packages/LiftEngine`
- Macro Track: `Apps/MacroTrack`, `Packages/SystemCore`, `Packages/SystemStore`, `Packages/HealthBridge`, `Packages/NutritionEngine`, `Packages/FoodDatabase`, `Packages/FoodIntelligence`, `Packages/MealPlanner`, `Scripts/catalogs.manifest`
- Mind Track: `Apps/MindTrack`, `Packages/SystemCore`, `Packages/SystemStore`, `Packages/SystemAI`, `Packages/MindEngine`, `Scripts/catalogs.manifest`

(`python3 Scripts/generate-project.py --packages <App>` prints each app's packages; keep these lists in step when an app gains one.)

**Environment variables**: Macro Track's and Mind Track's workflows need the secret `CATALOG_TOKEN`, a fine-grained GitHub token with read-only Contents access to this repo, so `ci_post_clone.sh` can download the catalogs. Optional: `RUN_PACKAGE_TESTS=0` on a workflow skips the package tests (GitHub runs them anyway).

**What the scripts do** (`Apps/<App>/ci_scripts/`, each one line calling `Scripts/xcode-cloud.sh`):

- `ci_post_clone.sh` fetches the app's catalogs, or does nothing for Lift Track.
- `ci_pre_xcodebuild.sh` runs the tests of the packages the app links before a Test action builds, so a failing engine test stops the build.
- `ci_post_xcodebuild.sh` writes TestFlight's "What to Test" for each archive from the recent commits that touched the app.

**Watch app**: the Lift Track archive includes the Watch app and its complication; no separate workflow.

**Mac**: Mind Track runs on Apple silicon Macs as the iPad app (Designed for iPad), so the same archive serves the Mac. Lift Track and Macro Track have that turned off.

## Catalogs

The catalogs (`off.db`, `supplements.db`, `japanese.db`, `spanish.db`) aren't in git. After rebuilding one, run `Scripts/publish-catalogs.sh` (uploads them all as a new private release and rewrites `Scripts/catalogs.manifest`) and commit the manifest; CI and Xcode Cloud then fetch the new ones. Whether the ODbL catalog is published publicly is still undecided.
