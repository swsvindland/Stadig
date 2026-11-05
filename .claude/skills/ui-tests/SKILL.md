---
name: ui-tests
description: Run and debug the few XCUITest tests in Apps/<App>/UITests (first run, the offer and the tabs) and the App Store screenshots beside them, for Stadig Lift, Stadig Macro and Stadig Mind. Use when onboarding or the offer changes, when a UI test fails or is flaky, or when a screen in the store set moves.
---

# UI tests

Each app has `Apps/<App>/UITests` (XCTest; Swift Testing can't drive UI) in the `<App>UI` test plan, which retries a failed test once. There are few on purpose: first run, the offer and a seeded launch through every tab, beside `StoreScreenshots`, which isn't a test. Run one class with `ONLY=<TestClass> Scripts/build.sh ui lift|macro|mind` after a change to onboarding or the offer; leave off `ONLY` for all of them, which is for releases.

Don't add a UI test for a new flow. What it decides goes in a unit test (`Apps/<App>/Tests` or the engine package), and the screen gets looked at in the running app (the `run-app` skill). The suites went from 127 tests to 22 on 2026-11-05, and [docs/testing.md](../../../docs/testing.md) says why: one that's added has to be a flow the owner never sees in daily use, where a break costs a new user or a sale.

## Launching

Use the helpers in `UITests/Support`: they launch with `-uiTesting` (in-memory store, no Health, notification, speech or camera prompts, no StoreKit, animations off) plus the arguments a test asks for:

```swift
let app = XCUIApplication.launched(["-seedSampleData", "-tab", "plan"])
```

Every app's DEBUG launch arguments are in `docs/<app>.md`. Start a test as close to the screen under test as they allow, rather than tapping through onboarding every time; one test per app covers onboarding itself.

## Finding things

- By accessibility identifier, always: `app.buttons["today.startSession"]`. Identifiers are `screen.element` in lowerCamelCase (`plan.nextBlock`, `logger.search`, `session.answer`). Add them in the view with `.accessibilityIdentifier(...)`; they don't change what VoiceOver says.
- Tabs by their labels, through `app.openTab("Plan")` in `UITests/Support` (the plan pins English and the US region): it taps the iPhone's tab bar, or on an iPad the sidebar, since the iPad's tab bar along the top shows a section's name in place of its tabs. `-tab` starts on any destination.
- Every test runs on the iPhone and the iPad (`Scripts/build.sh ui <app> ipad`). [docs/testing.md](../../../docs/testing.md) has the iPad's patterns.
- An identifier on a bare stack is given to every element inside it, over their own: give an identified stack `.accessibilityElement(children: .contain)` first. A `Table` or `List` may not expose its own identifier: wait for a row.
- Never by index or coordinates, never by copy that's likely to change.

## Waiting

- `XCTAssertTrue(element.waitForExistence(timeout: 10))` before touching anything that appears after work (seeding, a sheet, a computed plan). No `sleep`.
- Seeded launches run real engines: allow 20 seconds for the first screen on CI.
- A test that's flaky is a bug in the test or the app. Find the race; don't raise the retry count.

## What a good UI test checks

- One user flow per test, named for it (`testLoggingAFoodFromSearchUpdatesToday`).
- Assert the outcome a person would see (a value changed, a row appeared, a screen opened), not intermediate taps.
- Keep each test independent: every launch starts from an empty in-memory store.

## Debugging

In Stadig Macro: `app.toolbarItem(_:title:)` finds a toolbar button an iPad may have folded into More, and `app.logButton("search")` finds a way to log on either device.

Failures leave an `.xcresult` under `<DerivedData>-results/` (the path is printed with the failure); open it in Xcode for the screenshot and element tree at the failure. `app.debugDescription` prints the tree from inside a test. For a hosted-test hang at launch, check the app skips permission prompts under `-uiTesting`.
