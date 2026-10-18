---
name: ui-tests
description: Write, run and debug the XCUITest end-to-end tests in Apps/<App>/UITests for Lift Track, Macro Track and Mind Track. Use when adding a UI test for a flow, when a UI test fails or is flaky, or when adding accessibility identifiers for tests.
---

# UI tests

Each app has `Apps/<App>/UITests` (XCTest; Swift Testing can't drive UI) in the `<App>UI` test plan, which retries a failed test once. Run with `Scripts/build.sh ui lift|macro|mind`.

## Launching

Use the helpers in `UITests/Support`: they launch with `-uiTesting` (in-memory store, no Health, notification, speech or camera prompts, no StoreKit, animations off) plus the arguments a test asks for:

```swift
let app = XCUIApplication.launched(["-seedSampleData", "-tab", "plan"])
```

Every app's DEBUG launch arguments are in `docs/<app>.md`. Start a test as close to the screen under test as they allow, rather than tapping through onboarding every time; one test per app covers onboarding itself.

## Finding things

- By accessibility identifier, always: `app.buttons["today.startSession"]`. Identifiers are `screen.element` in lowerCamelCase (`plan.nextBlock`, `logger.search`, `session.answer`). Add them in the view with `.accessibilityIdentifier(...)`; they don't change what VoiceOver says.
- Tabs can use their labels (`app.tabBars.buttons["Plan"]`): the plan pins English and the US region.
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

Failures leave an `.xcresult` under `<DerivedData>-results/` (the path is printed with the failure); open it in Xcode for the screenshot and element tree at the failure. `app.debugDescription` prints the tree from inside a test. For a hosted-test hang at launch, check the app skips permission prompts under `-uiTesting`.
