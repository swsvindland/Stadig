# Stadig, the hub

The hub plans everything outside work or school. You tell it when you work or study, and it fits the gym, meals and study around that, with what's left protected as free time. It adapts when life changes, including when you tell it nothing.

It lives in `Apps/Hub` (display name Stadig, bundle `dev.svindland.stadig.hub`, URL scheme `stadig`) over `Packages/HubEngine`. It runs on iPhone, iPad, the Mac and Vision Pro. It's free, with no purchase code: it can't see whether another app is unlocked, and how it's sold is decided before release (`docs/decisions.md`).

## What it does

- **Today** is a card for what's next, over the day's six parts. The card's button opens the app that does the thing ("Open Stadig Mind"). The hub logs nothing, so that's all a button here ever does. Work and the commute pass by themselves, with nothing to tick. Parts already gone say Earlier. A part you're out of says Out.
- **Week** is a bar for each day, this week or next: gym, classes, meals, study, work and the commute in order, on a track of sixteen waking hours, so a full day looks full and the rest is plainly room. Tap one to see that day.
- **Rhythm** is the normal week. Work or school is a schedule you give it, not something it places: 9 to 5, alternate Fridays, university, shifts, nothing fixed, adjusted by hand, or said in your own words. Sleep and clear evenings are set here. Below them, what the plan knows from each app, and which app said so.
- **Plans changed** is one tap, and optional. "I'm out tonight" asks for no reason and closes the evening and the night. Tapped later in the day it also closes the parts already gone, so tonight's blocks move to another day rather than to a morning that's over. "Lighter week" means fewer study blocks and a shorter gym session, and ends on Sunday. Doing neither is just as fine: what doesn't happen moves on by itself.
- **Free time** is whatever's left. It's never named or given a clock time, and nothing here suggests what to do with it.

Saying a schedule goes through `ScheduleAssistant`: plain rules first, the same on every device, and Apple's on-device model only for what they can't read. Both fill the same draft and `ScheduleReader.draft` checks it, so a model can't put anything impossible on the screen. You always see the draft and confirm it. It decides nothing. Without a model, a sentence the rules can't read leaves you the presets.

## How it's built: publish inputs, not a plan

A weekly plan file would go stale: nothing here runs in the background, so if the hub isn't opened on a Monday, a shift worker's blocks would land in shifts. So the hub publishes what it knows, and one pure function answers for any date, in any app, with nothing to go out of date.

| File | Written by | What it is |
|---|---|---|
| `hub/rhythm.json` | the hub | `Rhythm`: the work pattern, wake and bed, clear evenings, the day's start |
| `hub/changes.json` | the hub | `[DayChange]`: out tonight and lighter weeks, merged per item with tombstones, kept six weeks |
| `apps/knowledge/blocks.json` | Stadig Mind | `BlockAsk`: blocks left per course, each day's weights, pins, what's finished, the blocks it last laid out |
| `apps/macroTrack/meals.json` | Stadig Macro | `MealRhythm`: the usual parts for meals, and today's eaten ones |
| `core/profile.json`, `apps/liftTrack/summary.json` | Stadig Lift | Training days, classes, recent sessions (as before) |

- **`WorkPattern`** is an anchor Monday, a cycle of N weeks of seven days, each a list of `DaySpan`s (minutes from that day's midnight, ends past 1440 for overnight shifts), an optional end date, and dated overrides. Past a term's end, or on a roster day with no entry, the answer is "unknown", never free, and `usualParts` applies.
- **`DayShape`** turns those into a day's parts: 4 a.m. to 4 a.m., open if there's a free run of 45 minutes. Two or more commitments make a day packed. Clear evenings are chosen from the pattern alone, so every app reaches the same ones.
- **`BlockPlanner.layout`** is the one layout. Mind and the hub both call it, Mind on its live state and the hub on the `BlockAsk`. If `algorithm` differs because the apps are on different builds, the hub shows the blocks Mind last published instead of predicting. Asks up to a week old lay out exactly as Mind does (`HubParityTests`).
- **`HubPlanner`** puts a day together. It's a pure function of `HubInputs`: nothing is stored, so what wasn't done has moved on by itself. Classes go first, at their set time, and stay even when a part is tight, running on into the next one. The lift is what moves, to the next part with room, or it waits. Anything published more than 28 days ago is ignored: the app may be gone.

The other apps stay whole without the hub. No file means today's behaviour, and each app's strip and Mind's rhythm only appear for someone who uses it.

- **Stadig Mind** reads the rhythm and changes. A lighter day counts like a review day, with no stacking. A lighter week caps the ledger, so skipping Mind all week invents no misses. Under a rhythm its grid is read-only, with a link to Rhythm.
- **Stadig Lift** caps a lighter week's session at two thirds, to the nearest five minutes and no less than half an hour. Its weekly quota doesn't change.
- **Each app's Today** has a one-line "Your day" strip of what's left, from `HubPlanner.ahead`, opening the hub.

## Its own state and sync

The rhythm and changes are records in the hub's own `RecordStore` (`iCloud.dev.svindland.stadig.hub`), mirrored to the shared files. The newest rhythm wins either way, and changes merge per item. `FamilySync` carries the `hub/` files to the person's other devices through the family container, which is how the other apps there hear about them, and `ICloudArrival` holds a second device on a wait rather than setup. Either route ends the wait, because either sets the rhythm.

Dates are stamped in whole seconds. A file round-trips dates to the millisecond, and a stamp that didn't come back the same would look like a change on every read, which would wake every app for ever.

## Not in the first version

Stats and quests from the doc's hub loop, family Discipline, reminders, the phone's calendar, Watch, widgets, and suggestions for free time.

## DEBUG launch arguments

- `-inMemoryStore` keeps nothing, with a scratch shared container.
- `-seedSampleData` fills an empty hub with alternate Fridays, a commute, the gym, classes, meals and four courses.
- `-resetData` erases the hub's store first.
- `-tab week|rhythm` opens a tab.
- `-showPlansChanged` opens the sheet.
- `-uiTesting` as in every app.

Stadig Mind's `-seedRhythm` shows its grid following a rhythm without the hub.
