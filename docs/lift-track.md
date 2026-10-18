# Lift Track: how the doc maps to the code

## SystemCore: the shared core

Everything the hub and every app must agree on lives here, so scores are identical wherever they're computed. It contains:

- **Models**
  - sessions (`SessionSummary`: "a session happened, here are the metrics")
  - logged sets and the three-tap `SetRating`
  - stats, quests, recommendations and goals
  - the published `AppSummary`
  - the shared profile, so setup is asked once
  - nutrition phases, life modes, measurements, mobility tests and endurance benchmarks
- **Strength scoring** (`StrengthStandards`, `StrengthEstimator`). Symmetric Strength style: each lift category's estimated 1RM is scored against bodyweight-relative standards with allometric scaling.
  - Only free-weight variants with a known ratio count. Machine weights are never converted.
  - Imbalances become priorities, e.g. "legs are well ahead of upper body, so upper body comes first".
- **RPE trust calibration** (`TrustState`, `Calibration`)
  - Trust starts from experience: novices 0.3, 1–3 years 0.5, 3+ years 0.7.
  - It moves only on evidence. A rep-out right after a rated set reveals the true reserve, and a heavier later set proves more was left.
  - Contradictions count more than confirmations, because "0–2 left" is often right by chance.
  - Machines (safe to fail) calibrate it. Free-weight ratings use the result.
  - Trust is rebuilt from the session history every time, so devices never disagree.
- **Set-to-set autoregulation** (`Autoregulation`)
  - Easy bumps the weight, or the reps when load steps are coarse.
  - Just right holds. Missed drops slightly ("missed reps are just data").
  - Finding-weight sets keep moving until a set rates Just right.
  - With low trust, verification pushes run on safe setups only: machines, or a rack with safeties.
- **Progression and stalls** (`Progression`, `Stalls`)
  - The target reps in reserve fall across the block, RP-style.
  - Fine increments progress by load. Coarse ones (dumbbells, stacks, bodyweight) use double progression.
  - Deloads and injury ramps adjust the targets. A deload during a ramp scales the load actually lifted, so an assisted lift gets more help, not less, and loads stay on the gym's steps.
  - A session is the sets logged with no gap of more than three hours, so a workout that runs past midnight is one session.
  - A stall is three or more weeks without a new best. It's read by phase: expected in a cut, a recovery problem when beat up, a programming problem otherwise. Each reading comes with a progressive-overload prompt, built on the top set of the last session that wasn't a deload.
- **Failure tiers** (`FailurePolicy`)
  - Safe to fail from day one.
  - Fail with setup once earned, and only with pins.
  - Never to failure for some lifts.
  - Rep-outs are capped per session and concentrated in the assessment and check-ins. Low-trust lifters stop free-weight rep-outs at form breakdown.
  - There are no rep-outs while a lift ramps back after an injury, check-ins included.
- **Fatigue Budget** (`FatigueBudget`). Hidden, never shown as a level.
  - Systemic and local cost per set, with failure multipliers (deadlifts are high).
  - Martial arts and other outside training spend the same budget.
  - Sleep, HRV, resting heart rate, soreness, joint pain, energy, performance trend and life stress all feed it.
  - "Beat up and stalled" reduces systemic cost before total work. Stacked signals call an early deload, but only after at least two loading weeks.
- **Scheduler and life modes** (`BlockScheduler`, `LifeModes`)
  - Blocks are 5+1 weeks by default, 3–8 by context: shorter in a cut, longer in a bulk and for beginners.
  - Vacations reflow the block: near the deload they become it; early in a block they cut it short. A trip that starts during the deload keeps the deload's start and stretches its end through the trip.
  - Crunch mode (time, equipment, food dials), injury mode (joints and severity, with a re-entry ramp) and illness mode (above the neck vs systemic).
  - Re-entry weeks, and the system-wide `SystemCalendar` of deloads.
  - A deleted life mode is kept as a tombstone and shared like an edit. The newest edit or delete of each period wins, so a vacation deleted in one app stays deleted in the others and on the person's other devices.
  - A period must end on or after its start, an injury has to say where it is, and only an injury or illness can be open-ended.
- **Discipline**: a rolling four-week adherence rate.
  - The target is the 80–90% band. Above it earns nothing extra, and one miss barely dents it.
  - Rest is part of the plan. "Didn't log" is unknown, not failure.
  - Vacation, illness and exempt crunch days never count.
- **Endurance, Agility and Physique**
  - Endurance: heart-rate zones, heart-rate-guided rest with minimums for heavy compounds, heart-rate recovery between sets, benchmarks.
  - Agility: five mobility tests, with the weakest becoming the limiter (a tie goes to the same test every time), and "see a physio" when a test hurts or worsens.
  - Physique: shoulder-to-waist and waist-to-height ratios, a tape body-fat estimate as a soft signal, and gaps described in neutral words. The body weight it uses is the one measured last: Health's, or one typed on the tape on a later day.
- **Steps** (`Steps`): a daily aim, never a stat or a streak.
  - It starts from your usual count (the four weeks before the current phase began), not a universal 10,000. Days under 1,000 steps (the phone on a desk) and illness days are unknown.
  - In a cut it heads for your usual plus about 2,000, at least the floor (8,000, or 7,000 from 60, where the benefit levels off in large cohort studies); a usual count over 12,000 is held. Otherwise it holds the usual count, lifted to the floor if it's under, and nothing over 10,000 is prescribed.
  - Each calendar week's aim is last week's average plus 1,000, never under the usual count and never past the target, so a missed week doesn't raise the next.
  - It's judged as the last seven days' average. It asks for something (a walk) only when there's something to do: always in a cut, otherwise while building to the floor or when steps slip more than 1,000 under the aim.

## ExerciseLibrary

The partial library from the first pass (258 exercises, every id kept) is now fully tagged, plus mobility drills, dynamic warm-ups, static stretches and conditioning pieces. Each entry carries:

- movement pattern
- muscles
- joints loaded, with stress levels
- systemic and local fatigue, stimulus and the failure multiplier
- safety tier
- strength-category mapping (free weights only)
- load basis
- default rest and reps by goal

Injury filtering is deterministic: an exercise is excluded when it stresses the injured joint at or above a threshold set by severity, and the person can add exercises back or take more out. `Scripts/build_library.py` regenerates `library.json` from frozen source tags.

## SystemStore

Each app owns its own **SwiftData + CloudKit** database: one generic `RecordRow`, one JSON payload per record, CloudKit-compatible. On top of that it provides:

- **Records:** schema versioning and step-by-step migration from day one, newest-wins dedupe of rows CloudKit delivers twice, and soft deletes that sync. Changes that sync in while an app is open are announced (`observeChanges`), so Lift Track shows them without a relaunch, and a local save updates only its own kind of record in the cache.
- **The shared App Group container** (`group.dev.svindland.stadig`): versioned envelopes, coordinated writes, and change notifications across apps. It holds the profile, life modes, the calendar, each app's summary, Macro Track's nutrition summary and the hub's recommendations and quests. Life modes are at schema 2, with deletes as tombstones. A summary or calendar is rewritten only when its content changes.
- **Backups:** the full backup file and restore (merge, newest wins), and CSV export. A backup restores only into the app that wrote it: another app's is refused before anything is written. CSV fields that start like a formula get a leading apostrophe.

## HealthBridge

- **Reads** body weight, height, sleep, HRV, resting heart rate, VO₂ max, heart-rate samples, daily steps (merged across iPhone and Watch the way Health shows them), and workouts other apps wrote. Those workouts are mapped to activity types with an estimated intensity and imported as outside activities.
- **Writes** strength workouts (keyed by sync id, so edits replace them), waist and body fat. Deleting a measurement removes its waist and body-fat samples, and clearing a field removes that one.
- **On watchOS**, `LiveWorkoutSession` streams heart rate. A workout whose mirroring to the iPhone fails is discarded, not left running.
- **Under tests**, `HealthBridge.shared.disable()` turns Health off for the process: no prompts, empty reads, no writes.

## LiftEngine and the app's feature modules

| Doc item | Where |
|---|---|
| Onboarding (days, time, equipment, experience) | `OnboardingView`. Goals as outcomes, schedule, equipment, units, experience, outside activities, basics, the phase question, Health. It reuses a shared profile another app wrote. Units default to kg and cm everywhere but the US. A birth year that would make someone under 10 or over 100 shows in red and isn't saved, so the age stays unknown (the same in Settings). On a second device or after a reinstall, settings, a gym and a block that sync in are kept rather than replaced by a new assessment, and the app moves to its tabs as soon as they arrive. New settings are saved under one id on every device, so two devices set up apart end up with the newer settings. |
| Assessment block | `ProgramGenerator` (`.assessment`, with safe-to-fail anchors) and `Assessment.status`, which writes the weekly "what we've learned" notes. Experienced lifters with proven ratings can finish early. |
| After the assessment | `Assessment.nextBlock`: Macro Track's phase if published, a neutral block while Macro Track is still deciding, otherwise the one-tap answer. One plan by default, with a "Why?". A next block accepted while the current one is still running starts the day after it ends, so the current block keeps its deload and check-in; Plan shows "Next block starts <day>" in place of "Plan the next block" until then, and the next block's deload is on the shared calendar too. An assessment finished early ends the day before the next block starts. |
| Program generator (mesocycles, elastic time budget) | `ProgramGenerator` |
| Live session (colour ratings, autoregulation, rest timer) | `LiveSession`, a pure state machine shared by phone and Watch, plus `SessionScreen` and `SetLogger`. |
| Physique | `BodyView`: tape measurements, ratios, gaps, waist trend, progress photos (stored at most 1,400 px on the long side and shown from smaller copies decoded off the main thread; never analysed). |
| Outside activities | Health imports, recurring declarations, and the quick log with the martial-arts fields (class type, sparring rounds, rounds before gassed). An imported workout deleted in Lift Track stays deleted; one deleted in the Health app stays in Lift Track. |
| Deloads and life modes | `BlockScheduler` and `LifeModes`; editors under `LifeModes/`; the Plan tab's week strip; "Deload this week" on Today when the Fatigue Budget calls an early deload. Until it's taken, Plan, the calendar and today's session keep the planned weeks. Today's session and the assessment's weeks follow a vacation's reflow, like the calendar. |
| Check-ins | `CheckInView`: the mobility tests and the conditioning benchmark. A test marked "It hurt" needs a result ("Can't" or a count) before the check-in can be saved, and "Record it" is on only when the benchmark will be saved. |
| Apple Health | `AppModel.refreshHealth`: at launch, on each return to the app (at most every ten minutes) and whenever Health reports a new workout or weigh-in. Deleting a measurement takes its samples out of Health. |
| Widgets | `WidgetBridge` and `Widgets/`: today's session as Today plans it (with the planner's swaps and crunch mode's minutes), "Today" or "Next: <weekday>" for the day the widget draws, and "Open Lift Track for today's plan" once that day has gone by. |
| Export and backup | Settings → Your data: CSV files, a `.liftbackup` file, and restore. Backup and restore run off the main thread with a progress row, and restore takes only a Lift Track backup. |
| Purchase (StoreKit one-time unlock) | `Purchases` and `PaywallView`, with `LiftTrack.storekit` for testing in Xcode. |
| Apple Watch app | `Watch/`: see below. |
| Accessibility | Ratings always show colour, symbol and words together; Dynamic Type throughout; VoiceOver labels on controls. |

The program generator works like this:

- **Split** by days per week.
- **Exercise selection**
  - The scored classic lift goes in main slots.
  - Stimulus is weighed against fatigue on a log scale, so cheap isolation can't crowd everything else out.
  - Exercises that are working stay. Stalled ones rotate out.
- **Volume** by experience and phase, plus priorities. These come from strength imbalances, physique gaps, the mobility limiter, lagging endurance and hub recommendations, and auto-prioritisation can be switched off.
- **Fatigue Budget pass**
  - It spends the systemic budget on high-SFR options, swapping the costliest lifts before trimming sets.
  - Declared classes spend the same budget.
  - Cheap local volume is added for lagging physique areas.
- **Elastic time budget**: each block has a minimum, a desired length and a priority, and goals reorder the priorities.
  - **30 minutes:** ramp-up sets are the warm-up, the limiter drill happens in the rests, two compounds are supersetted, and conditioning becomes a quest.
  - **60 minutes:** five easy minutes on a bike or rower and three drills, the limiter slot, the main lifts, a few accessories and brief conditioning.
  - **90 minutes:** a fuller warm-up, more sets and a 20–30 minute conditioning finisher.
  - Time the lifting doesn't use goes to more sets first (main lifts up to four work sets, accessories up to three), but only as far as the week's recovery budget allows, then to conditioning; no lift is ever a single set. When the budget is what keeps a session short, it says so ("About 45 minutes today, under your 60…") rather than leaving the hour feeling unfinished.
- **"Short on time today?"** refits the day to 30, 45, 60 or 90 minutes. A refit weighs the same fatigue, priorities and recommendations as a new block and gives the same day each time. Lengthening a 30-minute day undoes its supersets and the drills in its rests.

**Session planning** turns a day into exact sets:

- ramp-up sets, and rep-outs placed on safe-to-fail anchors first, judged on the exercise actually done after any swap, so a stand-in that isn't safe to fail gets none
- deloads keep Zone 2 and mobility
- check-ins land at the end of the deload
- crunch mode gives the minimum effective dose, with equipment stand-ins
- injuries swap out what they must, and injury ramps ease lifts back in
- a head cold means light work only
- a gym with a sauna or steam room gets an optional session at the end, outside the session's time. Setup asks (no preset assumes one), and Settings → Gym → Recovery changes it. Changing the gym's kind keeps the rooms, and the exercises taken out or added back. Rooms run hot and cold, so you read the thermometer and the minutes follow: the dose is minutes weighted by heat (twice as hard every 6 °C / 11 °F hotter, so 10 minutes at 190 °F is more than 20 at 175 °F), starting at ten minutes' worth at 80 °C (176 °F), capped by how hot the room is, and moved by how the last one felt (easy +15%, too much −20%, two just-rights in a row +5%). Time, temperature, rating and heart rate are kept apart from the lifting, so they never count as sets or calibrate ratings.

**Analysis** produces the "Do this next" actions. Each one ends in a concrete step, e.g. "Next session, 82.5 kg for 3×5" for a stall. When Macro Track data exists, it adds cross-app context such as "Protein was under target 4 of the last 7 logged days." Strength trends read each lift by its own load basis, so less help on an assisted lift counts as progress. It also produces the day's quests (three at most), the training discipline score, and the summary published for the hub.

**Steps** show on the Today tab whenever there's an aim: today so far against it, the last seven days and their average, where it's heading and why. Without one, the card asks to connect Health (or waits for a week of steps). On a rest day with the week behind, a quest offers the gap as a brisk walk ("20-minute walk"), but not on lift or class days, while ill, with a hip, knee or ankle injury, or once today reaches the aim. A long day on foot nobody logged (15,000 steps and 7,000 over the usual) spends the Fatigue Budget as walking; a logged hike counts once, as the hike. The last eight weeks of steps and the aim are published for Macro Track. Health is asked again for steps only by people who already connected it.

**Life modes** are added from Today and Plan. In the editor, moving "From" past "Until" moves the end with it, "Until" offers only days from the start on, and Save stays off for a period that can't apply. "Until it's better" (no end yet) is offered only for an injury or illness; a vacation or crunch another app saved with no end shows "Until", so it can be given one. "End it now" ("It's better: ramp back in" for an injury, "I'm better" for an illness) ends a period yesterday. One that started today is called off if it's a vacation or crunch; an injury or illness keeps today, and its ramp or lighter week back starts tomorrow. A period still to come has nothing to end: Delete cancels it.

## The Watch

The iPhone keeps the Watch's application context current: today's plan, the gym, trust, and recent history for the plan's exercises and their likely swaps. The Watch then runs the session on its own with the same `LiveSession` engine:

- the crown sets load and reps, and double tap is Done
- the three rating buttons
- rest with live heart rate, ending early once heart rate recovers (accessories only)
- conditioning with heart-rate zones
- a quick feedback screen

The finished session comes back to the phone both live and queued. The Watch's workout session saves it to Health. A Watch session left unsaved for more than six hours (the Watch died or restarted mid-session) is sent to the phone as it stood at its last logged change, without feedback, rather than dropped. A file the Watch can't read is renamed `<name>.unreadable-<seconds>.json` rather than written over.

The complication shows the next session. Once that session's day has gone by, it says to open Lift Track on the iPhone. Whenever the Watch app comes back on screen with no context or an old one, it asks the phone for today's, and keeps asking, live and queued, until a newer one arrives.

When the session runs on the iPhone instead, starting it asks the Watch for a workout (`HKHealthStore.startWatchApp`). The Watch shows a heart-rate screen and mirrors the workout back (`startMirroringToCompanionDevice`), sending each reading over it. The phone shows live bpm in the session header, zones against the aim in the warm-up and conditioning (logged as minutes per zone), and ends heart-rate-guided rests early. At the end the Watch saves the workout under the session's id, with heart rate and energy, and the phone doesn't save a second one. If the session's end doesn't reach the Watch (out of range, or its workout already over), the phone saves the workout itself. Stopping the heart-rate screen on the Watch, or the system ending it (another workout app starting, say), discards the Watch's workout, and the phone saves the workout to Health itself at the end. When the session has nothing to keep, or Save to Health is off, the phone tells the Watch to discard its workout.

**In the gym:** "Do this now" on any exercise moves it (and its superset partner) ahead when the next machine is taken. Tapping a logged set corrects its weight, reps or rating, and the sets still to come are worked out again from the corrected log. Tapping the weight types it in, and holding − or + keeps stepping. With no history, the weight starts from the strength standards (scored lifts) or a bodyweight ratio for the movement and equipment, scaled for experience and sex, so a 400 lb leg press isn't fifty taps from an empty sled. A typed weight over 1,500 kg is refused. Swapping an exercise partway through keeps the sets already logged under the exercise they were done on (in the session, its record, the analysis and the CSV export), and the replacement's first weight never comes from the exercise it replaced. "Add a set" isn't offered on conditioning or the sauna and steam room, so a second bout can't overwrite the first. When a rest's time runs out, the logger comes up for the next set, and the minimised session and the Live Activity move on with it. A heart-rate recovery only ends a rest that's still running.

**Finishing:** a session with nothing logged saves nothing and shows no summary. One with only a sauna or steam room in it is kept, and counts as the day's session. A session's day is the day where it was recorded, so travelling afterwards doesn't move it. A session left open for more than six hours is saved as it stood, ending at its last logged change, and its summary shows at the next launch. A session in progress survives an app update that adds fields to it; a `live-session.json` that can't be read is moved aside to `live-session.unreadable.json`.

## DEBUG launch arguments

- `-seedSampleData` fills an empty store with a lifter three weeks into the assessment. Every session runs through the real planner, live session and autoregulation.
- `-inMemoryStore` keeps nothing between launches. The store lives in memory and never syncs, and the shared container, the session in progress and the widget snapshot go to a fresh temporary folder. So a sample run no longer reads or writes what the other apps publish (Macro Track's phase, the hub's recommendations), and the home-screen widget doesn't show it. It still uses Health and can ask for permissions.
- `-uiTesting` is what the UI tests launch with: everything `-inMemoryStore` does, plus no Health, no permission prompts and no animations. There are no rest notifications, Live Activity, Watch connection or StoreKit either. The other arguments work alongside it.
- `-resetData` erases the store and the session in progress first.
- `-unlocked` skips the purchase (only matters once purchases are switched back on).
- `-gymSauna` gives the gym a sauna, for the recovery screen.
- `-startSession` starts today's session.
- `-tab plan|progress|body` opens a tab.

`SIM_DEBUG=1 swift test --filter simulationReport` in `Packages/SystemCore` prints every simulated lifter's sessions and calibration evidence. `PRINT_PROGRAMS=1 swift test` in `Packages/LiftEngine` prints generated programs.

## Tests

The rules are tested in the packages ([package-tests.md](package-tests.md)). The app's own tests check the wiring: the app model over a real store, the files it writes, links, the widget and the screens.

**Unit and integration tests** (`Apps/LiftTrack/Tests`, Swift Testing, 72 tests in 9 suites) build their own `AppModel` with `init(store:shared:liveURL:widgetURL:)`, over an in-memory store and a temporary shared container (`Tests/Support/TestApp`), and put in their own Watch and Health (`AppModel.WorkoutHandOff`) where a test needs them. A second model over the same install is a relaunch; a second container is another app on the same phone. Under the test host the app builds no model of its own and starts nothing: no Health, Watch connection, StoreKit or notifications.

- **App model:** onboarding (fresh, reusing another app's profile, a second device keeping synced settings and block), settings kept under the one id every device uses (and settings saved before it still read), sample data, a session planned, logged, finished and seen after a relaunch, empty, heat-only and discarded sessions, a Watch record saved once, store changes made elsewhere, and the model deallocating.
- **Session left open:** `live-session.json` across a relaunch, heart-rate-only writes throttled, one left over six hours saved and shown as finished, an empty one dropped, an unreadable one moved aside.
- **Shared container:** the summary and calendar published and not rewritten when unchanged; Macro Track's phase and the hub's recommendations read; life modes from another app, deletes as tombstones both ways, the newest edit winning, invalid periods refused; the "End it now" rules.
- **Links and widgets:** `lifttrack://start` and `lifttrack://session`; the widget snapshot matching Today; the iPhone widget's and the complication's wording on later days.
- **Backups and migrations:** older settings, measurement and life-mode records; export then import onto a fresh install; another app's backup refused.
- **Planning:** the plan following the analysis's block, minutes refits, a next block planned ahead waiting for its start, an assessment finished early, a new block built on the one running now, the early deload taken only when offered, Health imports saved once and their deletes sticking.
- **Format and entry:** loads, durations, temperatures and RIR; the thermometer's steps; typed loads (decimal commas, the 1,500 kg cap, rounding to the gym) and reps.
- **Session tools:** the starting load (prescription, this exercise's earlier set, then a strength-standards guess), the Live Activity's content, progress photos stored at 1,400 px.
- **The Watch and Health:** the workout saved once, by the Watch, or by the phone when the session's end doesn't reach the Watch or there's no Watch; the Watch's workout thrown away when Save to Health is off or nothing was logged; a heart-rate recovery ending a rest only while it runs; Health's weight against one typed on the tape later.

**UI tests** (`Apps/LiftTrack/UITests`, XCUITest, 9 tests) launch with `-uiTesting` plus the arguments the screen needs, and find elements by accessibility identifier (`today.startSession`, `logger.done`, …). `UITests/Support/Launch.swift` declines a leftover permission alert before each launch.

- **Launch and onboarding:** a seeded launch shows every tab; a first run goes through onboarding to Today.
- **Session:** start from Today, log and rate a set, skip a rest, finish and save; minimise and resume; discard; correct a logged set.
- **Screens:** Settings and CSV export; adding and deleting a vacation on Plan; adding a measurement on Body.

Run them with `Scripts/build.sh unit lift` (the app's tests and its packages' tests) and `Scripts/build.sh ui lift`, on the checkout's own test simulator (see [testing.md](testing.md)). After a build, `Scripts/leaks.sh lift` runs `leaks` on the seeded app on Today, Plan, Progress, Body and a started session.
