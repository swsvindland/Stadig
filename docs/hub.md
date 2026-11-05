# Stadig, the hub

The hub plans everything outside work or school. You tell it when you work or study, and it fits the gym, meals and study around that, with what's left protected as free time. It adapts when life changes, including when you tell it nothing.

It lives in `Apps/Hub` (display name Stadig, bundle `dev.svindland.stadig.hub`, URL scheme `stadig`) over `Packages/HubEngine`. It runs on iPhone, iPad, the Mac and Vision Pro. It's free, with no purchase code: it can't see whether another app is unlocked, and how it's sold is decided before release (`docs/decisions.md`).

## What it does

- **Today** is a card for what's next, over the day's six parts. The card's button opens the app that does the thing ("Open Stadig Mind"). The hub logs nothing, so that's all a button here ever does. Work and the commute pass by themselves, with nothing to tick. Parts already gone say Earlier. A part you're out of says Out.
- **Week** is a bar for each day, this week or next: gym, classes, meals, study, work and the commute in order, on a track of sixteen waking hours, so a full day looks full and the rest is plainly room. Tap one to see that day.
- **Rhythm** is the normal week. Work or school is a schedule you give it, not something it places: 9 to 5, hybrid, alternate Fridays, university, shifts, nothing fixed, adjusted by hand, or said in your own words. Sleep and clear evenings are set here. Below them, what the plan knows from each app, and which app said so, including when Stadig Macro is in use but hasn't given meal times.
- **Hybrid** sets each day as office, home or off, the office's hours, and how much of the day is worked at home before and after it. The commute falls between the home hours and the office, and moves them out of its way if it grows. A day at home has no commute. Tapping Hybrid again opens the week rather than resetting it.
- **Stats** is the eight stats from every app, each with its score, its trend and the app it came from. There's no overall level. A stat two apps publish, like Discipline, shows their average with each app's own number beneath it. Older than 28 days counts as nothing.
- **Moving** a class or the gym is a tap on it in Today: pick a part of the day, for just this day or every week. Which classes you do and how long they run stay Stadig Lift's. When they sit is the hub's, so Lift's Today and Mind's planning follow the move.
- **Plans changed** is one tap, and optional. "I'm out tonight" asks for no reason and closes the evening and the night. Tapped later in the day it also closes the parts already gone, so tonight's blocks move to another day rather than to a morning that's over. "Lighter week" means fewer study blocks and a shorter gym session, and ends on Sunday. Doing neither is just as fine: what doesn't happen moves on by itself.
- **Free time** is whatever's left. It's never named or given a clock time, and nothing here suggests what to do with it.

Saying a schedule goes through `ScheduleAssistant`: plain rules first, the same on every device, and Apple's on-device model only for what they can't read. A sentence about home and the office gets its own reading (`readHybrid`), or goes to the model if that finds too little: read as a plain day, its "8 hours" would hide the rest. Both fill the same draft and `ScheduleReader.draft` checks it, so a model can't put anything impossible on the screen. You always see the draft and confirm it. It decides nothing. Without a model, a sentence the rules can't read leaves you the presets.

## How it's built: publish inputs, not a plan

A weekly plan file would go stale: nothing here runs in the background, so if the hub isn't opened on a Monday, a shift worker's blocks would land in shifts. So the hub publishes what it knows, and one pure function answers for any date, in any app, with nothing to go out of date.

| File | Written by | What it is |
|---|---|---|
| `hub/rhythm.json` | the hub | `Rhythm`: the work pattern, wake and bed, clear evenings, the day's start, classes moved for good |
| `hub/changes.json` | the hub | `[DayChange]`: out tonight, lighter weeks and one-day moves, merged per item with tombstones, kept six weeks |
| `apps/knowledge/blocks.json` | Stadig Mind | `BlockAsk`: blocks left per course, each day's weights, pins, what's finished, the blocks it last laid out |
| `apps/macroTrack/meals.json` | Stadig Macro | `MealRhythm`: the usual parts for meals, and today's eaten ones |
| `core/profile.json`, `apps/liftTrack/summary.json` | Stadig Lift | Training days, classes, recent sessions, stats |
| `apps/macroTrack/summary.json`, `apps/knowledge/summary.json` | Stadig Macro, Stadig Mind | Stats |

- **`WorkPattern`** is an anchor Monday, a cycle of N weeks of seven days, each a list of `DaySpan`s (minutes from that day's midnight, ends past 1440 for overnight shifts), an optional end date, and dated overrides. A span of kind `home` is work with no commute; older builds read it as `work`, so the file's schema didn't change. `HybridWeek` builds these and reads them back for editing. Past a term's end, or on a roster day with no entry, the answer is "unknown", never free, and `usualParts` applies.
- **`DayShape`** turns those into a day's parts: 4 a.m. to 4 a.m., open if there's a free run of 45 minutes. Two or more commitments make a day packed. Clear evenings are chosen from the pattern alone, so every app reaches the same ones.
- **`BlockPlanner.layout`** is the one layout. Mind and the hub both call it, Mind on its live state and the hub on the `BlockAsk`. If `algorithm` differs because the apps are on different builds, the hub shows the blocks Mind last published instead of predicting. Asks up to a week old lay out exactly as Mind does (`HubParityTests`).
- **`HubPlanner`** puts a day together. It's a pure function of `HubInputs`: nothing is stored, so what wasn't done has moved on by itself. A meal eaten outside the usual times still shows, ticked, in the part it was eaten. Classes go first, at their set time, and stay even when a part is tight, running on into the next one. The lift is what moves, to the next part with room, or it waits. Anything published more than 28 days ago is ignored: the app may be gone.

The other apps stay whole without the hub. No file means today's behaviour, and each app's strip and Mind's rhythm only appear for someone who uses it.

- **Stadig Mind** reads the rhythm and changes. A lighter day counts like a review day, with no stacking. A lighter week caps the ledger, so skipping Mind all week invents no misses. Under a rhythm its grid is read-only, with a link to Rhythm.
- **Stadig Lift** caps a lighter week's session at two thirds, to the nearest five minutes and no less than half an hour. Its weekly quota doesn't change.
- **Each app's Today** has a one-line "Your day" strip of what's left, from `HubPlanner.ahead`, opening the hub.

## Its own state and sync

The rhythm and changes are records in the hub's own `RecordStore` (`iCloud.dev.svindland.stadig.hub`), mirrored to the shared files. The newest rhythm wins either way, and changes merge per item. `FamilySync` carries the `hub/` files to the person's other devices through the family container, which is how the other apps there hear about them, and `ICloudArrival` holds a second device on a wait rather than setup. Either route ends the wait, because either sets the rhythm.

Dates are stamped in whole seconds. A file round-trips dates to the millisecond, and a stamp that didn't come back the same would look like a change on every read, which would wake every app for ever.

## Not in the first version

Quests from the doc's hub loop, family Discipline, reminders, the phone's calendar, Watch, widgets, and suggestions for free time.

## DEBUG launch arguments

- `-inMemoryStore` keeps nothing, with a scratch shared container.
- `-seedSampleData` fills an empty hub with alternate Fridays, a commute, the gym, classes, meals and four courses.
- `-seedHybrid` with `-seedSampleData` makes the week a hybrid one.
- `-showHybridEditor` opens the hybrid week on the Rhythm tab.
- `-resetData` erases the hub's store first.
- `-tab week|stats|rhythm` opens a tab.
- `-day sun` shows that day of this week, and `-showMove "Muay Thai"` opens the move sheet for that item on it.
- `-showPlansChanged` opens the sheet.
- `-uiTesting` as in every app.

Stadig Mind's `-seedRhythm` shows its grid following a rhythm without the hub.
