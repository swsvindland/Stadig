# CI/CD

Two systems share the work. **GitHub Actions** checks every push cheaply: formatting, the generated projects, and every package's tests. **Xcode Cloud** builds, tests and ships the apps: it runs each app's test plans and its packages' tests, archives, and sends builds to TestFlight. GitHub's macOS minutes bill at ten times Linux ones on a private repo, so the app builds live in Xcode Cloud's monthly hours instead.

## What runs when

| Push to | GitHub Actions (`CI`) | Xcode Cloud, per app the push touches |
|---|---|---|
| any branch | lint, the generator check, every package's tests with warnings as errors | **Branch** workflow: the app's packages' tests, then its unit and integration test plan |
| `main` | the same | **Main** workflow: packages, unit plan and UI plan, then an archive to TestFlight (internal testers) |
| `release/<app>-<version>` | the same | **Release** workflow: the same tests, then an archive to TestFlight (external testers), ready to submit for review |

Xcode Cloud's column is the design, not what runs yet. What runs (checked 2026-11-14) is one workflow per app, `Default`: it starts on a push to any branch, whatever files changed, or by hand on `main`, and it archives for iOS, macOS and visionOS, each prepared for App Store Connect, then gives the iOS build to the `default` TestFlight group. The macOS and visionOS archives were added on 2026-11-14. Until then there were no Mac or Vision Pro builds to submit. So every push to any branch archives three platforms of both apps, which costs Xcode Cloud hours; the Branch, Main and Release split below would cut that. No Test action runs, so the unit and UI plans don't run there. Adding `Test <App>` and `Test <App>UI` would close that gap. Until then the app tests only run from `Scripts/build.sh unit` and `ui`, and the UI tests only before a release.

Also: on Mondays GitHub runs every package's tests under the thread and address sanitizers, and `CI` can be started by hand with **apps** ticked to build every app for every platform and run their unit (iPhone and Mac) and UI tests on GitHub (useful when Xcode Cloud's hours run low; about 25 macOS minutes per app, which a private repo on the free plan bills at ten times). `Site` tests the support form's function (`pnpm test`) and builds the marketing site on pushes that touch `Site/`.

Until the Xcode Cloud workflows below exist, the only thing that compiles the apps on a push is `Default`'s archives: GitHub only lints and runs the package tests. Creating them is the one manual step left.

"Touches" comes from each Xcode Cloud workflow's file filter (below), so a Stadig Macro change doesn't rebuild Stadig Lift.

## Branches

- **Work on a branch** named `feature/<topic>` or `fix/<topic>` (Claude Code sessions make `claude/<name>`; all three start Xcode Cloud's Branch workflow). Push as often as you like: GitHub and Xcode Cloud's Branch workflows say whether it's good.
- **`main` is always shippable.** Merge a branch once its checks pass. Every push to `main` puts a fresh internal TestFlight build of each app it touched on your devices (turn on Automatic Updates in TestFlight).
- **Release from a release branch.** When an app is ready for the App Store:
  1. Branch `release/lift-1.1` (or `macro-…`) from `main`.
  2. On the release branch, set that app's entry in `VERSIONS` in `Scripts/generate-project.py` to the version you're shipping, run it, commit.
  3. On `main`, bump the same entry to the next version (1.2) straight away: TestFlight refuses builds of a version that's already been approved, so `main` must never build a shipped version.
  4. Both apps are free (since 2026-11-11): purchases are off in each app's `Purchase/Purchases.swift` (`enabled: false`), and there are no products to set up. [app-store-connect.md](app-store-connect.md) has what's on the store, and what a price would take.
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
| Actions | Test: scheme `<App>`, test plan `<App>`, iOS, one iPhone simulator | Test `<App>`; Test `<App>UI`; Archive for iOS, macOS and visionOS (three Archive actions), TestFlight (Internal Testing Only) | Test `<App>`; Test `<App>UI`; Archive for iOS, macOS and visionOS, TestFlight and App Store |
| Post-actions | none | TestFlight Internal Testing: your internal group | TestFlight External Testing: your beta group |

**The app's folders** (the file filter: start if any file here changes):

- Stadig Lift: `Apps/LiftTrack`, `Packages/SystemCore`, `Packages/ExerciseLibrary`, `Packages/SystemStore`, `Packages/SystemPurchases`, `Packages/HealthBridge`, `Packages/LiftEngine`
- Stadig Macro: `Apps/MacroTrack`, `Packages/SystemCore`, `Packages/SystemStore`, `Packages/SystemPurchases`, `Packages/HealthBridge`, `Packages/NutritionEngine`, `Packages/FoodDatabase`, `Packages/FoodIntelligence`, `Packages/MealPlanner`, `Scripts/catalogs.manifest`

(`python3 Scripts/generate-project.py --packages <App>` prints each app's packages; keep these lists in step when an app gains one.)

**Environment variables**: Stadig Macro's workflows need the secret `CATALOG_TOKEN`, a fine-grained GitHub token with read-only Contents access to this repo, so `ci_post_clone.sh` can download the catalogs. Optional: `RUN_PACKAGE_TESTS=0` on a workflow skips the package tests (GitHub runs them anyway).

**What the scripts do** (`Apps/<App>/ci_scripts/`, each one line calling `Scripts/xcode-cloud.sh`):

- `ci_post_clone.sh` fetches the app's catalogs, or does nothing for Stadig Lift.
- `ci_pre_xcodebuild.sh` runs the tests of the packages the app links before a Test action builds, so a failing engine test stops the build.
- `ci_post_xcodebuild.sh` writes TestFlight's "What to Test" for each archive from the recent commits that touched the app.

**Every platform from one target**: each app is one multiplatform target (iPhone, iPad, the Mac and Apple Vision Pro, `SDKROOT = auto`), so one bundle id, one App Store Connect record and one purchase cover every device (universal purchase). Xcode Cloud archives once per platform: add an Archive action for iOS, one for macOS and one for visionOS to the Main and Release workflows. In App Store Connect, add the macOS and visionOS platforms to each app's record (the app page → **Add Platform**) before the first upload of those archives. The Mac archive is sandboxed and signed with `Config/<App>-macOS.entitlements` (no HealthKit: Health isn't on the Mac).

**Watch apps**: the iOS archives of Stadig Lift and Stadig Macro include their Watch apps and complications; no separate workflow. The Mac and visionOS archives leave them out. Xcode Cloud's automatic signing can't register a bundle id or turn on a capability, so a new target's id (`….watchkitapp`, `….watchkitapp.widgets`) and any new capability (iCloud, App Groups) must exist on developer.apple.com first. Archive once in Xcode with the team signed in, or register them by hand. Otherwise the export fails with "Automatic signing cannot register bundle identifier". A Watch app's background modes go in `UIBackgroundModes` (`remote-notification` for CloudKit's pushes). `WKBackgroundModes` takes only session types such as `workout-processing`, and App Store Connect rejects anything else there (ITMS-90362, shown in Xcode Cloud only as "Preparing build for App Store Connect failed").

**iCloud, once, before the first device build**: every app lists its own container (`iCloud.dev.svindland.stadig.lift`, `.macro`) and the family's, `iCloud.dev.svindland.stadig`, which carries the shared files (profile, calendar, summaries) between devices (`SystemStore`'s `FamilySync`). Xcode's automatic signing offers to create the family container the first time an app builds for a device with it; or create it in the developer portal (Identifiers → iCloud Containers) and tick it for each app id. After a development build has synced once, deploy each container's schema to production in the CloudKit Console (Schema → Deploy Schema Changes), or TestFlight and App Store builds can't sync. The symptom: every device keeps its data to itself, a second device opens on onboarding, and Settings says "Not syncing" with "iCloud's schema has no CD_RecordRow yet, so changes stay on this device" (or "iCloud turned down some changes" when iCloud couldn't be asked why). The server's own words, "Cannot create new type CD_RecordRow in production schema", are only in Console, or on a Mac: `/usr/bin/log show --last 1h --predicate 'process == "LiftTrack" AND eventMessage CONTAINS "production schema"'` (zsh's own `log` command shadows the tool, so give its path).

**Local Mac builds**: `Scripts/build.sh mac <app>` signs ad hoc with only the entitlements that need no profile (the sandbox, files, network, microphone), so it builds and runs on any Mac without an account; that build keeps its data on the Mac and says "This device only". Xcode's Run and the archives sign with the team and the full entitlements.

## Catalogs

The catalogs (`off.db`, `supplements.db`) aren't in git. After rebuilding one, run `Scripts/publish-catalogs.sh` (uploads them all as a new release, as private or public as the repository, with the data's licence notice in its notes, and rewrites `Scripts/catalogs.manifest`) and commit the manifest. The release is how `off.db` and its recipe are offered under the ODbL, so its tag has to sit on a commit that holds the scripts that built it: `main` by default, or `CATALOG_TARGET=<a pushed branch>` when they aren't merged yet; CI and Xcode Cloud then fetch the new ones. They stay private while the repo is, which TestFlight doesn't mind: `CATALOG_TOKEN` reads them. They must be public before the App Store release (`agent-docs/decisions.md`, "Public access to `off.db`").
