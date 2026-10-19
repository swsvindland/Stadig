# Verified, and not yet

**Verified**

- **Package tests.** All 11 packages pass `swift test` from a clean build with warnings as errors: 700 tests in 116 suites, zero warnings. ExerciseLibrary 31, FoodDatabase 86, FoodIntelligence 80, HealthBridge 20, LiftEngine 74, MealPlanner 22, MindEngine 144, NutritionEngine 83, SystemAI 8, SystemCore 112, SystemStore 40. All of them ran clean under the thread and address sanitizers.
- **App tests** passed in the quality pass's last runs, each app on its own iPhone 18 Pro simulator (iOS 27), with the unit runs built with warnings as errors.
  - Lift Track: 72 unit and integration tests in 9 suites, and 9 UI tests: each tab, onboarding, a session from Start to its summary, minimising and resuming, discarding, correcting a logged set, Settings' export, adding and deleting a vacation, and adding a measurement.
  - Macro Track: 87 unit and integration tests in 15 suites, and 13 UI tests: each tab, onboarding, logging from search and its Undo, quick add, the weigh-in from the quick-log bar, widget links in place of an open sheet, starting the recommended phase, ticking off a supplement, opening Settings, an illness started there, and the CSV export.
  - Mind Track: 73 unit and integration tests in 15 suites, and 12 UI tests: each tab and its links, setup through to the first session (and that it needs a focus course), starting from Today, a session ended early and one answered to its summary, Settings, a vacation and an illness, a book onto the shelf, and logging an episode.
  - No UI test needed a retry in the final runs. Lift Track's UI run left the simulator's App Group untouched.
- **Leaks.** No leaks in the apps' own code on seeded screens: Lift Track's launch, Plan, Progress, Body and a running session; Macro Track's launch, Plan, Progress, search, Supplements and Settings; Mind Track's launch, Plan, Progress, a session, the shelf and Settings. The leaks found were the system's, with no frame in the apps' code: allocations in SwiftUI, UIKit, dyld and Foundation Models, or ones made before logging started. At the time `Scripts/leaks.sh` took a run with a single leak for one it couldn't read, and ran lines of the leaks report as shell commands, so Macro Track's screens were checked with a corrected copy of it and Mind Track's Settings with `leaks` by hand. Lift Track's screens and Mind Track's others came from the script as it was. The script has been fixed since. Each app model also has a test that it deallocates.
- **Builds.** With warnings as errors (`STRICT=1`), the `LiftTrack` scheme (iPhone/iPad app, widgets, Live Activity, embedded Watch app), the `LiftTrackWatch` scheme (the Watch app and its complications), the `MacroTrack` scheme (app, widgets, controls) and the `MindTrack` scheme build with zero errors and warnings.
- **GitHub Actions.** The first push of `ci.yml` and `site.yml` to main (8dae263, 2026-10-19) passed: lint in 10 s and every package's tests in 3 minutes on the `xcode-27` runner, with the apps job skipped as designed, and the site built in 16 s.
- **iPhone 18 Pro Max simulator**
  - Onboarding on the persistent store creates the assessment block. The first session prescribes "find weight" sets.
  - `-seedSampleData` runs three weeks of real engine sessions. Today shows "What we've learned", including the overhead-press imbalance and "you can finish early".
  - "Short on time? 30" refits the day: warm-up and mobility fold into ramp-up sets and rests, and conditioning moves to later.
  - The live session works throughout:
    - timed drills, then ramp-up sets with a short rest and plates per side
    - Easy on a working set raises the remaining sets with the reason shown
    - a 2.5-minute rest for heavy compounds, with ±15 s and skip
  - Plan: the week strip and priorities. "Plan the next block" generates a block headlined by the weakest lift, with a shoulder-gap lateral raise added. Accepting it starts a 5+1 week block.
  - Progress: all seven lift scores, within about 4% of the seeded lifter's true strength. Also the e1RM trend, discipline gauge, endurance, agility with its limiter, and ratings.
  - Body: ratios and gaps in neutral words.
  - Settings.
- **Apple Watch Series 12 simulator** (driven with real taps by the agent that built it):
  - home, set, rating, reps after a miss, rest, timed drills, conditioning, the exercise list, finish and summary
  - restore after relaunch
  - the outbox record format
  - the complication snapshot
  - large text

- **Macro Track, iPhone 18 Pro simulator**
  - Onboarding with Lift Track's profile already in the shared container: it asks only about recent dieting and weight, then Health shows the nutrition and weight permissions. Day 1 of 21.
  - The inline weigh-in, search ("greek yog" with natural portions like "1 container"), the portion screen, one-tap + with Undo, the time bar (a food logged "1h ago" lands an hour back on the timeline), the timeline of moments, the weigh-in from the quick-log bar (last weight prefilled, nudged and saved in four taps), and the barcode path (typed digits, since the simulator has no camera) finding Nutella in Open Food Facts.
  - Describe with the on-device model: "two eggs, toast with butter and a flat white" became eggs, toast, butter, and espresso plus whole milk for the flat white (440 kcal), logged in one tap. One-tap correction and "Search for…" work.
  - A meal picture with `-log photoLibrary -photo meal.jpg` (Stadig Tests Macro, 2026-10-18, the Info.plist without `SystemAIPrivateCloud`): an illustrated breakfast read on the device in 12.7 s into the review screen (egg, bacon, wheat bread, coffee) with no crash. Two faults showed, both older than the Private Cloud Compute fix: the bread came out as 500 g (1,370 kcal), and the bacon's portion read "2 slice cookeds".
  - With `-seedSampleData`: Today, the assessment card, the maintenance range, the recommendation with "Why?", the active plan after starting it, Progress (trend, intake against maintenance, discipline) and Settings with the catalogs' attribution.
  - Launch to a usable screen in under 2.5 s without seeding.
  - Live scanning with `-liveScanDemo` (iPhone 18 Pro Max): the package front named "Oat Crunch" and the unknown barcode kept; panning down a label taller than the screen, calories and fat confirmed first, then carbs and protein, with the hint following ("Keep going: still reading carbs and protein", then "Got it"); Apple Intelligence checked it as it went and named it "Oat Crunch Honey Almond"; saved with its barcode and vitamins, and logged. The Supplement Facts scan showed only the tracked lines in order (fish oil, lemon oil and rosemary left out), checked by Apple Intelligence, into the editor with 2 softgels.
  - Supplements and drinks, with `-seedSupplements` (iPhone 18 Pro Max): Today's doses by time of day with "Take all" and one-tap ticks (and unticks); the Supplements screen with grouped schedules ("1 tablet · morning and evening") and times; the editor on a NIH label; a Supplement Facts photo chosen from Photos read into 2 capsules, 25 mcg vitamin D, 200 mg magnesium, 15 mg zinc and L-theanine, named and added; search over the NIH labels; the Drinks card (a glass of water, one-tap coffee at 95 mg caffeine with Undo, fluid from drinks, caffeine left at bedtime); the cut-back sheet starting from the week's 268 mg average; and Settings' Tracking section.
- **Mind Track, iPhone 17e simulator** (launch arguments and screenshots; the simulator panel wasn't available for taps): the welcome screen within 2 s of launch, with the catalog opening in 33 ms; the first session's vocabulary test with "Don't know"; Today, Plan and Progress over `-seedSampleData`; warm-up reviews (a listening question, meaning questions with right and wrong feedback, the word card with reading and kanji); a maths lesson with its worked example and a typed problem, with fractions, powers and functions drawn natively; a writing item in extra practice; and the reading timer with last time's note. The app and engine build with zero errors and warnings.
- **Mind Track v2** (each subject on its own simulator, by launch arguments and screenshots): reading's test, focus blocks, the shelf and book finder, with a typed ISBN looked up live on Open Library (Pride and Prejudice); Spanish end to end with the catalog built, the four skill levels, scaffolds, dialogues and graded readers, speaking with `-fakeSpeech`; maths' timed numeracy block, statistics problems from real Lift Track data in the simulator, placement and per-strand Plan and Progress; writing's compose, notes, blind comparisons and trends on the iPad, with Vision reading a page set in a handwriting font. The four branches merged with 107 engine tests passing five runs in a row.

- **Every device (2026-10-18 night, branch `claude/everywhere`)**
  - Builds with warnings as errors: each app for iOS, macOS and visionOS, both Watch apps (Lift Track's and Macro Track's) and every widget extension; the generated projects match the generator; `Scripts/build.sh lint` is clean.
  - Package tests: 767 in 127 suites, warnings as errors (SystemCore 112, LiftEngine 87, ExerciseLibrary 39, SystemStore 48, HealthBridge 20, NutritionEngine 100, FoodDatabase 91, FoodIntelligence 80, MealPlanner 22, MindEngine 160, SystemAI 8).
  - App tests hosted in the Mac app (`Scripts/build.sh unit <app> mac`): Lift Track 85, Macro Track 112, Mind Track 91.
  - On this Mac, by eye, each app's new screens with `-seedSampleData -inMemoryStore`: Lift Track's Today, Plan, Program, Library and an exercise's detail, History, Progress, Body, the session window and Settings; Macro Track's Today (and a day back), Foods with its inspector, History, Meal Plan, Supplements, Progress, Plan, Settings and photo, describe and barcode logging; Mind Track's Today (with a session open and minimised), Plan, Progress, Shelf, Writing, Courses (words and maths), Settings, the book finder and a session's steps. Mind Track's session keys were pressed for real (2 picked a choice, Return moved on, Esc asked to end, typing then ⌘Return handed a piece in, a digit under the End dialog did nothing), and Lift Track's session window was closed, resumed, finished and discarded with the main window closed.
  - Macro Track's Watch app on a watchOS 27 simulator, before the review's fixes: Today, Log Again, Water, Supplements, the weigh-in dial and the complications (in a DEBUG gallery).
  - Each app's diff was reviewed by a separate agent, and every finding confirmed in the code was fixed (stale Mac settings panes writing over synced edits, sidebar-only tabs reachable on iPhone, a second Mind Track session replacing a running one, shelf edits undone by a running session, Health copies taken out for records that were only missing, Return logging the previous search's food, among others).

**Not verified**

- **Every device, on simulators and hardware.** The machine's simulator service was wedged for most of the night, so after the platform work nothing ran on an iPhone, iPad or Vision Pro simulator: the iPhone unit and UI tests, the new iPad UI tests (`Scripts/build.sh ui <app> ipad`), and the iPad and Vision Pro layouts by eye. The Watch app wasn't run again after its fixes.
- **Signing with the team.** Everything on the Mac ran ad hoc, without iCloud or the App Group. Not yet seen: the family iCloud container (`FamilySync`) carrying files between devices, CloudKit on the Mac, Vision Pro and the Watch, the App Group on the Mac, Macro Track's Health backfill on a device, Continuity Camera imports, the Mac's microphone in Mind Track, and the Mac apps in light mode.

- Mind Track: the check-in on screen, the speech voice's sound, whether other audio comes back when speech is stopped before it starts, the reading flow's page and reflection sheets, backup and restore from Settings (the model's restore is unit-tested), CloudKit sync, iPad and Mac layouts, and VoiceOver over the maths (the text it reads is unit-tested).
- Mind Track v2: a real barcode scan and cover photo (no camera in the simulator), Google Books (its keyless quota was spent), real speech and the first download of a language's speech model, drawing with Apple Pencil, the document camera and photo picker, the AI's blind pick (the on-device model picked "A" in both orders every time, so no second opinion was recorded), a check-in on screen, and iPhone layouts for writing and iPad for the rest.
- Macro Track's live scanning with a real camera: frame rate and focus on a phone, the torch, barcodes from the camera's detector, and labels that are curved, glossy or in poor light. The simulator ran it from `-liveScanDemo`'s rendered frames.
- Macro Track's supplements and drinks: a reminder's Taken button (notifications weren't exercised), Siri's "Take my supplements" and "Log water", scanning a supplement's barcode with the live camera, water and supplement writes to Health on a device, and the skip swipe.
- Macro Track: photo logging and label photos in the app (the package's evaluation ran them on the Mac; the simulator has no camera), the live barcode scanner, Private Cloud Compute (it needs Apple's managed entitlement, then `SystemAIPrivateCloud` in the Info.plist; until then the apps never use it), Siri and Shortcuts, the widgets and controls as rendered, Health writes on a device, and on-device AI timing on a phone.
- Macro Track paths with no tests yet: the live-scan state machine and its timeouts, the entry editor's load and save, the time picker, the label review's commas, thousands and duplicates, cancelling a meal plan while it's planning, and UI flows for live scanning, meal prep, supplements' "Take all" and Undo, and Progress's range.
- Camera fixes that need a real camera: Mind Track's barcode scans firing once, and its camera not starting after the scanner has closed; Macro Track's live frames parsed off the main actor.

- CloudKit sync between real devices: duplicate rows converging, an edit from another device reaching an open app (the app tests simulate it on one device), onboarding on a second device keeping the setup that synced, and life-mode deletes spreading as tombstones.
- A real iPhone ↔ Watch round trip. The two sides were checked separately against the same message format.
- The Watch changes from the 2026-10-18 quality pass ran on no simulator. There's no Watch test target, so they were only built: a stale session sent to the phone rather than dropped, "Do This Now" keeping supersets together, timers per set, the context request retried until answered, unreadable files set aside, logged sets shown under the exercise they were done on, and the complication's midnight entry (its wording is unit-tested through the phone's tests).
- Live heart rate on the Watch: heart-rate-guided early rest, heart-rate recovery between sets, and minutes per zone.
- The phone-led session's mirrored Watch workout (start from the phone, readings on the phone, the Watch saving it), and how it ends: Stop on the Watch discards the Watch's workout so the phone saves the only one, the phone saves the workout itself when the session's end doesn't reach the Watch, and the Watch's workout is discarded when Save to Health is off or mirroring fails. It needs a real Watch with Developer Mode on.
- Haptics, the crown and double tap.
- Health on a device: reads, imports from other apps, the sync-id replace when saving workouts, a deleted measurement's samples leaving Health, Undo right after logging a food leaving nothing there, and a weigh-in deleted in Health leaving Macro Track (the app's handling of the deletes is unit-tested).
- Whether deleting a logged food leaves its food correlation in Health. `HealthBridge.deleteFoods` doesn't remove correlations, and a fix could crash (HealthKit raises an exception for some calls on correlation types), so it waits for a device: log a food, delete it, then query food correlations for its id.
- The Live Activity and widgets as rendered on the Lock Screen, Dynamic Island, Home Screen and watch face.
- StoreKit purchase and restore against `LiftTrack.storekit`. The `-unlocked` flag was used in testing instead.
- The iPad's layouts by hand: a session's two panes in a gym, drag to reorder, pointer hover and a hardware keyboard's shortcuts.
- VoiceOver.
- Xcode Cloud: nothing has run there. Its workflows still have to be created in App Store Connect ([ci-cd.md](ci-cd.md)).
- GitHub Actions: the Monday sanitizer job hasn't run on GitHub yet. The thread and address sanitizers have only run locally.

**Known gaps**

- The Watch doesn't recover an interrupted HealthKit workout. After a relaunch it starts a new one with the same sync id.
- A Watch session records as a single strength workout, conditioning included.
- A session run from the Watch saves its workout to Health even with Save to Health off: the phone's context (`PhoneContext`) doesn't carry the setting.
- The Watch's saved session isn't fully safe across an app update: `PhoneContext` and the `Gym` inside it still decode strictly, so a new required field would set a running session aside.
- A workout imported from Health and later deleted in the Health app stays in Lift Track. Whether to mirror those deletes is undecided.
- Progress photos saved before the quality pass stay large in the store and in sync (they were drawn at three times screen scale). New ones are stored at 1,400 px, and every photo displays downsampled.
- An assessment counts as complete only after its last day, or through "you can finish early". The final-week rule asks for more sessions than are scheduled, and its threshold is undecided.
- A typed body fat carries forward with no age limit, so a reading from months ago still beats this week's tape estimate and reaches Macro Track.
- Macro Track's onboarding allows 0 training days and publishes that to the shared profile, outside the shared range of 1 to 7.
- A weigh-in deleted in Health before a device's first read of changes stays in Macro Track, since a first read reports no deletions.
- A Macro Track phase ended partway through a week keeps that end in a new field. An older build on another device drops the field if it saves the plan again, and the phase then runs to its whole weeks, overlapping the diet break or mini-cut after it by up to 6 days.
- A Mind Track session saved by a newer version with an unknown purpose or attempt kind can't be read by an older one. Unknown courses are left out.
- Mind Track's "Read my handwriting" takes the strokes it read off the page by count. If any were erased while it was reading, that many strokes written meanwhile go too.
- Activities, weigh-ins, and Mind Track's sessions, test results and writing take their day from the phone's current time zone. Only Lift Track's sessions keep the zone they were logged in.
- The UI test plans retry a failed test once (`retryOnFailure`, at most 2 runs), so a flaky test could pass unnoticed.
- A few app tests read the real clock: two of Macro Track's model tests, and two of Mind Track's UI tests (one fails if a run crosses midnight, the other takes a different path on a rest day).
- Lint is clean with this Mac's swift-format; CI's runs the same command.
