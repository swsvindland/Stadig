# CLAUDE.md

Stadig ("The System"): three apps (Stadig Lift, Stadig Macro, Stadig Mind), each one multiplatform SwiftUI target for iPhone, iPad, the Mac and Apple Vision Pro (Stadig Lift and Stadig Macro also have Watch apps), as thin shells over twelve local Swift packages, plus the marketing site in `Site/`. The design doc ("The System — Hub Design") is the source of truth for product behaviour; [README.md](README.md) has the layout and commands, `docs/` the detail.

Names: anything a person reads (app text, Info.plist, StoreKit, the site, docs) says Stadig Lift, Stadig Macro and Stadig Mind, never "Lift Track", "Macro Track", "Mind Track" or "The System"; the family, the hub and the App Store bundle are Stadig. Code keeps its old names (`Apps/LiftTrack`, `LiftEngine`, `AppID.knowledge`, `SystemCore`), and identifiers (bundle and product IDs, the App Group, CloudKit containers) never change.

## Commands

```sh
Scripts/build.sh lint                  # swift-format --strict, as CI runs it
Scripts/build.sh format                # fix formatting in place
Scripts/build.sh test [Package]        # package tests (all, or one); STRICT=1 makes warnings errors
cd Packages/X && swift test --filter Y # one suite or test
Scripts/build.sh unit lift|macro|mind [ipad|vision|mac]  # an app's unit and integration tests (this checkout's own simulator; iPhone by default)
Scripts/build.sh ui lift|macro|mind [ipad|vision]        # an app's UI tests (ONLY=FastingUITests runs one class)
Scripts/build.sh ios|watch|macro|macro-watch|mind        # build an app for the iOS simulator (or a Watch app)
Scripts/build.sh mac|vision lift|macro|mind              # build an app for the Mac (runs on this Mac) or Vision Pro
Scripts/leaks.sh lift|macro|mind       # after a build: `leaks` on the app's seeded screens
Scripts/store-screenshots.sh [lift|macro|mind]  # recapture App Store screenshots into Store/ (Store/README.md)
python3 Scripts/generate-project.py    # after changing targets, settings, Info.plist keys or packages
```

Before calling a change done: lint clean, zero warnings, and the tests for what you touched pass (the package's tests for engine changes; `unit` for the app you changed when its screens or model changed). A change to an app's screens builds for every platform it runs on (`mac` and `vision` too) and runs the UI tests for that flow rather than the whole suite (`ONLY=<TestClass> Scripts/build.sh ui <app>`, plus `ipad` when it touches the iPad or desktop layout). The full UI suites, on the iPhone and the iPad, are for releases (the `release` skill): they take most of the time, so they don't run on every change. Say which you ran and which you didn't.

## Where code goes

- **One target per app, every platform.** Screens choose layouts by size class (compact keeps the iPhone design; regular, on iPad, the Mac and Vision Pro, gets the desktop one) and spell platform differences through `Platform/Adaptive.swift`, not scattered `#if`. Hardware a platform lacks (camera, Pencil, Health on the Mac) gets that platform's substitute, never a dead control.
- **Logic lives in a package, with tests.** Rules, calculations, planning, parsing, anything with a right answer: the engine package for that app (`LiftEngine`, `NutritionEngine`, `MindEngine`, …), or `SystemCore` when two apps or the hub must agree. Apps hold views, the app model, platform glue (Health, notifications, camera, widgets) and DEBUG seeding.
- **Shared contracts** between apps go through `SystemCore` models and `SystemStore`'s shared container, which `FamilySync` carries to the person's other devices through the family CloudKit container. Changing a published payload means a schema version bump and a migration test.
- **No third-party dependencies**, in apps or packages. Apple frameworks only.
- **Never edit `*.xcodeproj`, schemes or `*.xctestplan` by hand.** `Scripts/generate-project.py` writes them (CI fails if they drift). New files in an app's folders need nothing: targets use synchronized folders.

## Swift and SwiftUI conventions

- Swift 6 language mode, strict concurrency. App targets default to `@MainActor` isolation; packages are nonisolated by default. Heavy work (catalog queries, analysis over long histories, image and OCR work, JSON for big files) runs off the main actor.
- State is `@Observable` (Observation), injected with `.environment`. No `ObservableObject`/`@Published` in new code.
- Anything that outlives a call (NotificationCenter observers, timers, `Task`s that loop or await streams, delegates) captures `[weak self]`, is stored, and is cancelled or removed when its owner goes away. Long-lived singletons are the exception, and say so in a comment.
- Keep `body` cheap: no formatting, sorting or filtering of large collections inside it; compute in the model. Create formatters once (static), not per call.
- No force unwraps or `try!` on data from users, files, the network or the store; `fatalError` only for programmer errors that can't ship. Don't swallow errors that matter with `try?`: log them (`Logger`) or show them.
- Dates: pass `now`/`today` and a `Calendar` in; never compare `Date()` deep in logic. Mind time zones and DST.
- Interactive views get `accessibilityIdentifier("screen.element")` (for UI tests) and readable accessibility labels.
- Formatting is swift-format's (`.swift-format`: 4 spaces, 150 columns). A hook formats each Swift file Claude edits; don't fight it.
- Comments say why, not what, in the plain, specific voice the code already uses. Match the surrounding code.

## Tests

Swift Testing for everything but UI tests (XCTest). Engine behaviour gets package tests, including a simulated user when the behaviour plays out over weeks. App models are tested over an in-memory store and a temporary shared container. UI tests launch with `-uiTesting` plus the DEBUG launch arguments for the screen (listed in each app's doc) and find elements by accessibility identifier. Tests are deterministic: fixed dates, seeded randomness. Details: [docs/testing.md](docs/testing.md).

## Docs to keep current

- Behaviour or a new screen: the app's `docs/<app>.md` (and its DEBUG launch arguments).
- A product call made without the owner's sign-off: `docs/decisions.md`. Don't bury decisions in code.
- What was checked by hand on a simulator or device: `docs/verification.md`.
- New tests worth knowing about: `docs/package-tests.md`.
- Build, CI or release changes: `README.md`, `docs/ci-cd.md`, and this file. What's sold, and how: `docs/app-store-connect.md`.

## Working alongside other sessions

Several Claude Code sessions often work in this repo at once, sharing one checkout and one git index.

- Don't stage in the shared index and never `git add -A` or `git commit -a`: build commits from a private index (the `commit` skill has the steps), and commit only your own files.
- Prefer a worktree for multi-file work (`.claude/worktrees/`).
- Drive simulators by UDID, never `booted`. `Scripts/build.sh` gives each checkout its own DerivedData and its own simulators ("Stadig Tests", "Stadig iPad" and "Stadig Vision <checkout>"; `Scripts/build.sh simulator [ipad|vision]` prints the UDID), so sessions in different worktrees never collide. The Mac app launched for a check is yours to quit when done; `swift Scripts/window-shot.swift "<App>" out.png` captures just its window.
- Don't reset, amend or rebase another session's commits.

## CI/CD

GitHub Actions lints and runs every package's tests on every push; Xcode Cloud archives `main` to TestFlight and release branches (`release/<app>-<version>`) to the App Store; its Test actions aren't showing on `main`, so nothing runs the app tests for you. Versions live in `VERSIONS` in the generator; build numbers are Xcode Cloud's. [docs/ci-cd.md](docs/ci-cd.md).

## Skills

`.claude/skills/` has project skills for building and testing, running an app in the simulator, adding a feature, writing UI tests, adding a package, reviewing a change, committing safely, and releasing.
