---
name: add-feature
description: The end-to-end way to add or change a feature in Stadig Lift, Stadig Macro or Stadig Mind: engine logic and tests in the package first, then the SwiftUI screen, identifiers and UI test, then docs. Use when building a new screen, rule, recommendation or flow, or changing how an existing one behaves.
---

# Add or change a feature

Work in this order. Each step is small and checked before the next.

## 1. Find where it belongs

- Read the app's `docs/<app>.md` section for the area, and the design doc if the owner pointed at it. Product behaviour comes from there; if the doc is silent and you have to choose, choose, then record it in `docs/decisions.md`.
- Logic (a rule, a number, a plan, a parse) goes in the app's engine package, or `SystemCore` if another app or the hub must agree with it. The app gets views, model wiring and platform glue.
- Look for an existing type that already models the concept before adding one. The three apps mirror each other (`AppModel`, `StoredRecords`, `SampleData`, `Purchases`, `Platform/`): copy the established shape.

## 2. Engine first, with tests

- Write the logic in the package with Swift Testing tests next to the existing suite for that area. Pass `now`, `today` and a `Calendar` in; keep it pure.
- For behaviour that plays out over weeks (progression, maintenance estimates, spaced repetition, placement), extend the matching simulation (simulated lifter, eater, student, reader or writer) rather than only testing one step.
- If it changes a stored or shared payload: bump its schema version and add a decoding test for the old shape.
- `Scripts/build.sh test <Package>`.

## 3. The app

- The app model (`iOS/App/AppModel.swift`) exposes what the screen needs, computed once per change rather than in `body`.
- Views: `@Environment(AppModel.self)`, small subviews, no heavy work in `body`, formatters created once.
- Give every control a test will touch `.accessibilityIdentifier("screen.element")`, and make sure VoiceOver reads it sensibly.
- Long-lived observers, timers and tasks: `[weak self]`, stored, cancelled in `onDisappear`/`deinit` (or `.task`, which cancels itself).
- If it needs data to show, extend `SampleData` so `-seedSampleData` exercises it, and add a DEBUG launch argument if the screen is deep (open it directly).
- Purchases: check whether it sits behind the unlock (`Purchases`; see `docs/decisions.md`).

## 4. Tests in the app

- Wiring worth checking (the model publishes the right thing to the shared container, a deep link lands on the right step): `Apps/<App>/Tests`.
- The user-visible flow: a UI test in `Apps/<App>/UITests` (see the `ui-tests` skill).
- `Scripts/build.sh unit <app>` and `Scripts/build.sh ui <app>`.

## 5. Finish

- `Scripts/build.sh lint`, zero warnings.
- Update `docs/<app>.md` (behaviour, new launch arguments), `docs/package-tests.md` (notable tests), `docs/verification.md` (what you checked on a simulator).
- Run the `review-change` skill over the diff, then the `commit` skill.
