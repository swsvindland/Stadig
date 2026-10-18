# Testing

The logic is the product, so most tests live with the logic in the packages. The apps add tests of their own for what only they do (the app model over a real store, launch options, deep links, widget snapshots) and UI tests that drive each app like a person would.

| Layer | Where | Framework | Runs with | Runs in CI |
|---|---|---|---|---|
| Unit: engines and models | `Packages/<Package>/Tests` | Swift Testing | `Scripts/build.sh test` or `swift test` in the package | GitHub on every push; Xcode Cloud before each app's tests |
| Simulation: simulated lifters, eaters, students, readers and writers through the real engines | the same | Swift Testing | the same | the same |
| Integration: an app's model over an in-memory store, everything it publishes to the shared container, cross-app contracts | `Apps/<App>/Tests` | Swift Testing, hosted in the app | `Scripts/build.sh unit lift\|macro\|mind` | Xcode Cloud (the `<App>` test plan) |
| End to end: the app on a simulator, launched with seeded data | `Apps/<App>/UITests` | XCTest (XCUITest) | `Scripts/build.sh ui lift\|macro\|mind` | Xcode Cloud Main and Release (the `<App>UI` test plan) |
| Sanitizers: the package tests under TSan and ASan | | | `SANITIZE=thread Scripts/build.sh test` | GitHub, Mondays |
| Leaks: `leaks` on each app's seeded screens, counting only leaks whose allocation runs through the app's own code | `Scripts/leaks.sh`, `Scripts/classify-leaks.py` | | `Scripts/leaks.sh lift\|macro\|mind` after `Scripts/build.sh ios\|macro\|mind` | by hand, before a release |

What the package tests cover, suite by suite, is in [package-tests.md](package-tests.md).

## Running tests

```sh
Scripts/build.sh test                     # every package
Scripts/build.sh test LiftEngine          # one package
cd Packages/LiftEngine && swift test --filter StepAim   # one suite or test
Scripts/build.sh unit lift                # Lift Track's app tests (lift, macro or mind)
Scripts/build.sh ui macro                 # Macro Track's UI tests
SANITIZE=thread Scripts/build.sh test SystemStore
```

App tests run on a simulator of the checkout's own, "Stadig Tests <checkout>" (an iPhone Pro, created the first time; `Scripts/build.sh simulator` prints its UDID), with a DerivedData folder of its own, so they never take over a simulator or build another session is using. `SIMULATOR=<udid>` and `DERIVED_DATA=<path>` override them. Failures print the path of the full log and leave an `.xcresult` next to it (open it in Xcode for screenshots of UI test failures).

Opt-in reports: `SIM_DEBUG=1 swift test --filter simulationReport` (SystemCore), `PRINT_PROGRAMS=1 swift test` (LiftEngine), `PRINT_PLAN=1 swift test --filter SampleWeek` (MealPlanner), `MEAL_AI_EVAL=1 swift test --filter Evaluation` (FoodIntelligence, runs the real models on this Mac).

## Writing tests

- **New logic goes in a package, with its tests.** If a view model or the app model grows a rule, move the rule into the package and test it there; the app test then only checks the wiring.
- **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`) for everything except UI tests, which need XCTest.
- **Deterministic:** pass dates and calendars in rather than reading `Date()`; seed anything random; keep timing thresholds generous or out of unit tests. The simulations already use fixed seeds.
- **Catalog tests skip themselves** when a catalog isn't installed (`Scripts/fetch-catalogs.sh` gets them), so a fresh clone still passes.
- **App tests** create their app model over an in-memory store and a temporary shared container, never the real ones. The test host launches the app in a minimal mode under XCTest, so nothing touches Health, iCloud or notifications.
- **UI tests** launch with `-uiTesting` (an in-memory store, no permission prompts, no animations) plus the DEBUG launch arguments that set up the screen under test (`-seedSampleData`, `-tab plan`, …; each app's doc lists them). Find elements by accessibility identifier (`screen.element`, such as `today.startSession`), never by position, and wait with `waitForExistence` rather than sleeping. Each app's `UITests/Support` has the launch helpers.
- **Leaks:** an object that owns observers, timers or tasks gets a test that it deallocates (`weak var` after the scope ends, then `#expect(object == nil)`).
