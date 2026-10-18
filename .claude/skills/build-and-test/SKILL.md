---
name: build-and-test
description: Build, lint and test Lift Track, Macro Track, Mind Track and their Swift packages, and read the failures. Use after any code change before calling it done, when a build or test fails, or when asked to run the tests, check warnings, or run the sanitizers.
---

# Build and test

Everything goes through `Scripts/build.sh` from the repo root. It prints only errors, warnings and test summaries, and the path of the full log when something fails.

## Pick what to run

| You changed | Run |
|---|---|
| A package's sources or tests | `Scripts/build.sh test <Package>` (and the packages that depend on it: SystemCore → all of them) |
| An app's model, platform glue or launch handling | `Scripts/build.sh unit <app>` |
| An app's screens, navigation or identifiers | `Scripts/build.sh unit <app>` then `Scripts/build.sh ui <app>` |
| The generator | `python3 Scripts/generate-project.py`, then build every app it touched |
| Widgets, Live Activity, the Watch app | `Scripts/build.sh ios` / `watch` / `macro` |
| Anything, before committing | `Scripts/build.sh lint` |

`<app>` is `lift`, `macro` or `mind`. Package dependents: ExerciseLibrary → LiftEngine; FoodDatabase → FoodIntelligence, MealPlanner; NutritionEngine → MealPlanner; SystemCore → everything but SystemAI.

One suite or test: `cd Packages/<Package> && swift test --filter <SuiteOrTestName>`.

`STRICT=1` (what CI uses) turns warnings into errors. The code has zero warnings; keep it that way rather than relying on STRICT to catch them.

## Simulators

Each checkout (the main one, each worktree) gets its own simulator, "Stadig Tests <checkout>", created on first use, and its own DerivedData, `/tmp/system-dd-<checkout>`, so it never takes over a simulator or build another session is driving. `Scripts/build.sh simulator` prints the UDID and `Scripts/build.sh products` where the .app files land. `SIMULATOR=<udid>` and `DERIVED_DATA=<path>` override them. Never target `booted`.

The first `unit`/`ui` run in a checkout builds the app and its packages (a few minutes); later runs are incremental. Results land in `<DerivedData>-results/*.xcresult` (open in Xcode for UI test screenshots).

## Catalog tests

FoodDatabase, FoodIntelligence, MealPlanner and MindEngine have tests that need the catalogs in `Apps/MacroTrack/Catalogs` and `Apps/MindTrack/Catalogs`. Without them those tests skip. `Scripts/fetch-catalogs.sh` downloads them (needs `gh` signed in). In a fresh worktree, clone them from the main checkout instead: `cp -c <main>/Apps/MacroTrack/Catalogs/*.db Apps/MacroTrack/Catalogs/` (APFS clone, instant, no extra space), same for MindTrack.

## Sanitizers

`SANITIZE=thread Scripts/build.sh test [Package]` and `SANITIZE=address …`. CI runs both weekly. Use TSan after touching anything with locks, actors, `@unchecked Sendable` or `nonisolated(unsafe)`.

## Reading failures

- Swift Testing failures print `recorded an issue at File.swift:line`; the expectation's values are in the line after.
- A UI test failure: open the `.xcresult`, look at the failure screenshot and the element tree; most are a missing identifier or a missing wait.
- "isn't a member of the specified test plan": the plan was edited by hand or not regenerated; run the generator.
- Hosted app tests hanging at launch: something in the app's launch path is waiting on a permission or the network; the app must skip it under XCTest (see the app's `LaunchOptions`).

Report exactly what you ran and the result. If you skipped a layer (say, UI tests), say so.
