# Testing

The logic is the product, so most tests live with the logic in the packages. The apps add tests of their own for what only they do (the app model over a real store, launch options, deep links, widget snapshots) and UI tests that drive each app like a person would.

| Layer | Where | Framework | Runs with | Runs in CI |
|---|---|---|---|---|
| Unit: engines and models | `Packages/<Package>/Tests` | Swift Testing | `Scripts/build.sh test` or `swift test` in the package | GitHub on every push; Xcode Cloud before each app's tests |
| Simulation: simulated lifters, eaters, students, readers and writers through the real engines | the same | Swift Testing | the same | the same |
| Integration: an app's model over an in-memory store, everything it publishes to the shared container, cross-app contracts | `Apps/<App>/Tests` | Swift Testing, hosted in the app | `Scripts/build.sh unit lift\|macro\|mind`, on the Mac with `… mac` | Xcode Cloud (the `<App>` test plan) |
| End to end: the app on a simulator, launched with seeded data | `Apps/<App>/UITests` | XCTest (XCUITest) | `Scripts/build.sh ui lift\|macro\|mind`, the iPad layout with `… ipad` | Xcode Cloud Main and Release (the `<App>UI` test plan) |
| Sanitizers: the package tests under TSan and ASan | | | `SANITIZE=thread Scripts/build.sh test` | GitHub, Mondays |
| Leaks: `leaks` on each app's seeded screens, counting only leaks whose allocation runs through the app's own code | `Scripts/leaks.sh`, `Scripts/classify-leaks.py` | | `Scripts/leaks.sh lift\|macro\|mind` after `Scripts/build.sh ios\|macro\|mind` | by hand, before a release |

What the package tests cover, suite by suite, is in [package-tests.md](package-tests.md).

## Running tests

```sh
Scripts/build.sh test                     # every package
Scripts/build.sh test LiftEngine          # one package
cd Packages/LiftEngine && swift test --filter StepAim   # one suite or test
Scripts/build.sh unit lift                # Lift Track's app tests (lift, macro or mind)
Scripts/build.sh unit lift mac            # the same tests, hosted in the Mac app
Scripts/build.sh ui macro                 # Macro Track's UI tests
Scripts/build.sh ui macro ipad            # on the iPad, where the desktop layout runs
SANITIZE=thread Scripts/build.sh test SystemStore
```

App tests run on a simulator of the checkout's own, "Stadig Tests <checkout>" (an iPhone Pro, created the first time; `Scripts/build.sh simulator` prints its UDID), with a DerivedData folder of its own, so they never take over a simulator or build another session is using. A device after the app picks another of the checkout's own: `ipad` ("Stadig iPad", a 13-inch iPad Pro, for the regular-width layouts), `vision` ("Stadig Vision") or `mac` (this Mac, with the app signed ad hoc; see [ci-cd.md](ci-cd.md)). `SIMULATOR=<udid>` and `DERIVED_DATA=<path>` override them. Every UI test runs on both: the regular-width suites skip themselves on an iPhone (`XCTSkipUnless` on the idiom), and the iPhone's run on the iPad too, through the same helpers, unless they test something only the iPhone has (see below). Failures print the path of the full log and leave an `.xcresult` next to it (open it in Xcode for screenshots of UI test failures).

Opt-in reports: `SIM_DEBUG=1 swift test --filter simulationReport` (SystemCore), `PRINT_PROGRAMS=1 swift test` (LiftEngine), `PRINT_PLAN=1 swift test --filter SampleWeek` (MealPlanner), `MEAL_AI_EVAL=1 swift test --filter Evaluation` (FoodIntelligence, runs the real models on this Mac).

## Writing tests

- **New logic goes in a package, with its tests.** If a view model or the app model grows a rule, move the rule into the package and test it there; the app test then only checks the wiring.
- **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`) for everything except UI tests, which need XCTest.
- **Deterministic:** pass dates and calendars in rather than reading `Date()`; seed anything random; keep timing thresholds generous or out of unit tests. The simulations already use fixed seeds.
- **Catalog tests skip themselves** when a catalog isn't installed (`Scripts/fetch-catalogs.sh` gets them), so a fresh clone still passes.
- **App tests** create their app model over an in-memory store and a temporary shared container, never the real ones. The test host launches the app in a minimal mode under XCTest, so nothing touches Health, iCloud or notifications.
- **UI tests** launch with `-uiTesting` (an in-memory store, no permission prompts, no animations) plus the DEBUG launch arguments that set up the screen under test (`-seedSampleData`, `-tab plan`, …; each app's doc lists them). Find elements by accessibility identifier (`screen.element`, such as `today.startSession`), never by position, and wait with `waitForExistence` rather than sleeping. Each app's `UITests/Support` has the launch helpers.
- **UI tests on the iPad.** In regular width iPadOS puts the tabs in a bar along the top, where a section shows as one item (Lift Track's Training and Records, Macro Track's Food and Review, Mind Track's Library) that opens its first destination, and the whole sidebar is on the toggle at the bar's start. So tests move between tabs with `app.openTab("Progress")`, which taps the iPhone's tab bar or, on an iPad, opens the sidebar, taps the row and closes the sidebar again if it still covers the screen; `app.tabButton(_:)` is the button in either bar, and `-tab` starts a test on any destination. A flow the iPad does differently stays one test where it can (Macro Track's `logButton` is the quick-log bar's button or Today's toolbar's); a test of something only the iPhone has (Macro Track's entry sheet on Today) skips on the iPad with `XCTSkipIf` saying which iPad test covers it. Two things the iPad does that the iPhone doesn't: a number field's pad is a popover beside it, and a tap anywhere else only closes the popover, so close it before tapping on (Macro Track's `closeNumberPad`); and a toolbar's search can be a button until tapped (Macro Track's `foodSearchField`).
- **Keys.** `typeKey` delivers characters and ⌘ shortcuts to an iPad simulator (Lift Track's 2 and Space, Mind Track's 1 and ⌘1–⌘6), but not Return or Escape: not even Return to a search field with the cursor in it, where it's the system's own. Tests tap the button those keys stand for; Return and Escape on an iPad are checked by hand.
- **Containers.** SwiftUI gives a `Table`'s or a `List`'s rows to accessibility, and not always the container's identifier: wait for a row (`session.outlineItem`, a row's text) rather than the table. An identifier on a bare stack is given to every element inside it, over their own, so a stack that's identified as a whole (`session.screen`, `mealPlan.week`) gets `.accessibilityElement(children: .contain)` first.
- **Leaks:** an object that owns observers, timers or tasks gets a test that it deallocates (`weak var` after the scope ends, then `#expect(object == nil)`).
