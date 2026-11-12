# CLAUDE.md

Stadig ("The System"): two fitness apps (Stadig Lift and Stadig Macro), each one multiplatform SwiftUI target for iPhone, iPad, the Mac and Apple Vision Pro (each with a Watch app), as thin shells over ten local Swift packages, plus the marketing site in `Site/`. The design doc ("The System — Hub Design") is the source of truth for product behaviour; [README.md](README.md) has the layout and commands, `docs/` the detail.

Names: anything a person reads (app text, Info.plist, StoreKit, the site, docs) says Stadig Lift and Stadig Macro, never "Lift Track", "Macro Track" or "The System"; the family is Stadig. Code keeps its old names (`Apps/LiftTrack`, `LiftEngine`, `AppID.knowledge`, `SystemCore`), and identifiers (bundle and product IDs, the App Group, CloudKit containers) never change.

## Commands

```sh
Scripts/build.sh lint                  # swift-format --strict, as CI runs it
Scripts/build.sh format                # fix formatting in place
Scripts/build.sh test [Package]        # package tests (all, or one); STRICT=1 makes warnings errors
cd Packages/X && swift test --filter Y # one suite or test
Scripts/build.sh unit lift|macro [ipad|vision|mac]  # an app's unit and integration tests (this checkout's own simulator; iPhone by default)
Scripts/build.sh ui lift|macro [ipad|vision]        # an app's few UI tests, for releases (ONLY=PurchaseUITests runs one class)
Scripts/build.sh ios|watch|macro|macro-watch        # build an app for the iOS simulator (or a Watch app)
Scripts/build.sh mac|vision lift|macro              # build an app for the Mac (runs on this Mac) or Vision Pro
Scripts/leaks.sh lift|macro   # after a build: `leaks` on the app's seeded screens
Scripts/store-screenshots.sh [lift|macro]  # recapture App Store screenshots into Store/ (Store/README.md)
python3 Scripts/generate-project.py    # after changing targets, settings, Info.plist keys or packages
```

Before calling a change done: lint clean, zero warnings, and the tests for what you touched pass (the package's tests for engine changes; `unit` for the app you changed when its screens or model changed). A change to an app's screens builds for every platform it runs on (`mac` and `vision` too) and gets looked at in the running app (the `run-app` skill). UI tests are few on purpose: first run, the offer, a walk through the tabs and the store screenshots. They run before a release, on the iPhone and the iPad (the `release` skill), and with `ONLY=<TestClass> Scripts/build.sh ui <app>` after a change to onboarding or the offer. A new flow doesn't get a UI test: what it decides goes in a unit test. Say which you ran and which you didn't.

## Where code goes

- **One target per app, every platform.** Screens choose layouts by size class (compact keeps the iPhone design; regular, on iPad, the Mac and Vision Pro, gets the desktop one) and spell platform differences through `Platform/Adaptive.swift`, not scattered `#if`. Hardware a platform lacks (camera, Pencil, Health on the Mac) gets that platform's substitute, never a dead control.
- **Logic lives in a package, with tests.** Rules, calculations, planning, parsing, anything with a right answer: the engine package for that app (`LiftEngine`, `NutritionEngine`, …), or `SystemCore` when both apps must agree (the stats both show are its `StatsBoard`). Apps hold views, the app model, platform glue (Health, notifications, camera, widgets) and DEBUG seeding.
- **Shared contracts** between apps go through `SystemCore` models and `SystemStore`'s shared container, which `FamilySync` carries to the person's other devices through the family CloudKit container. Changing a published payload means a schema version bump and a migration test ([docs/shared-container.md](docs/shared-container.md) has the files, including what the removed hub and Stadig Mind left on devices).
- **No third-party dependencies**, in apps or packages. Apple frameworks only.
- **Never edit `*.xcodeproj`, schemes or `*.xctestplan` by hand.** `Scripts/generate-project.py` writes them (CI fails if they drift). New files in an app's folders need nothing: targets use synchronized folders.

## Swift and SwiftUI conventions

Write and review SwiftUI with the `swiftui-pro` skill (`.claude/skills/swiftui-pro`, Paul Hudson's). Where it and this file differ (one type per file, hard-coded spacing, the design's custom numerals), this file and `docs/design.md` win.

- Swift 6 language mode, strict concurrency. App targets default to `@MainActor` isolation; packages are nonisolated by default. Heavy work (catalog queries, analysis over long histories, image and OCR work, JSON for big files) runs off the main actor.
- State is `@Observable` (Observation), injected with `.environment`. No `ObservableObject`/`@Published` in new code.
- Anything that outlives a call (NotificationCenter observers, timers, `Task`s that loop or await streams, delegates) captures `[weak self]`, is stored, and is cancelled or removed when its owner goes away. Long-lived singletons are the exception, and say so in a comment.
- Screens are built from `Components/Stadig.swift` (the same file in both apps; change both): the `Ink` palette, `.numeral`, `Ruler`, `.inkCard`, `SourceChip`, `ScoreShape`. No system grouped greys, rings or extra accent colours on redesigned screens.
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
- Build, CI or release changes: `README.md`, `docs/ci-cd.md`, and this file. Both apps are free (purchases off); App Store Connect: `docs/app-store-connect.md`.
- The look (palette, numerals, the ruler, Your shape, what each device is for): `docs/design.md`.

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
