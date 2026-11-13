# The shared container

Stadig Lift and Stadig Macro each own their own database and publish small files for each other into the App Group container, `group.dev.svindland.stadig` (`SystemStore`'s `SharedContainer`). Each file is a versioned envelope, `{schemaVersion, writtenBy, writtenAt, payload}`, written atomically under file coordination, with a change notification the other app hears. The keys are the `SharedKey` extensions in `Packages/SystemStore/Sources/SystemStore/SharedContainer.swift`; the payload types are in `SystemCore`.

Stadig used to have two more apps: the hub (Stadig), which planned a day around work and showed the stats, and Stadig Mind. Both left this repo on 2026-11-11 (`docs/decisions.md`). What they wrote may still be on people's devices and in iCloud, so it's listed here too. Nothing reads it now.

## The files

| File | Written by | Read by | What it is |
|---|---|---|---|
| `core/profile.json` | Stadig Lift, Stadig Macro (whichever is set up first, then either) | both, and Macro's Watch app | `SharedProfile`: setup answers asked once, training days and recurring classes |
| `core/life-modes.json` | both | both, and Macro's Watch app | `[LifeModePeriod]`: vacations, crunch and the rest, merged a period at a time with tombstones (schema 2; version 1 files decode as they are) |
| `core/calendar.json` | Stadig Lift | Stadig Macro and its Watch app | `SystemCalendar`: the current block, deloads and check-ins |
| `apps/liftTrack/summary.json` | Stadig Lift | Stadig Macro and its Watch app; the stats | `AppSummary`: stats, recent sessions, strength, fatigue, measurements, steps |
| `apps/macroTrack/summary.json` | Stadig Macro | the stats | `AppSummary`: stats |
| `apps/liftTrack/scores.json`, `apps/macroTrack/scores.json` | each app its own, from its store | both, for the stats | `ScoreHistory`: the app's scores day by day, for how each has moved (schema 1, new 2026-11-13) |
| `apps/macroTrack/nutrition.json` | Stadig Macro | Stadig Lift | `NutritionSummary`: the phase, maintenance, day-by-day logging, a running fast |
| `apps/macroTrack/meals.json` | nothing now: Stadig Macro wrote it for the hub | nothing | When someone usually eats and what they'd eaten that day, by part of the day |
| `hub/rhythm.json` | nothing now: the hub wrote it | nothing | The work pattern, wake and bed, clear evenings, the day's start, classes moved for good |
| `hub/changes.json` | nothing now: the hub wrote it | nothing | Out tonight, lighter weeks and one-day moves, with tombstones |
| `hub/recommendations.json` | nothing, and the hub never did | nothing | Priorities for another app's plan |
| `apps/knowledge/summary.json`, `apps/knowledge/blocks.json` | nothing here: Stadig Mind wrote them | nothing | Its stats and its week of study blocks |

## What the hub left behind

The `hub/` files are frozen at whatever the hub last wrote, and since 2026-11-12 neither app reads them: there are no keys for them in `SharedContainer` any more, and the types they held (`Rhythm`, `DayChange`, `Recommendation`) are gone from `SystemCore`. Stadig Macro's `meals.json`, which only the hub read, isn't written any more either. Nothing deletes or rewrites any of them: they stay on devices and in iCloud as they are, and `FamilySync` and backups carry them by path like any other file.

For someone who had them, that changed two things:

- **Stadig Lift** shows a class at its own time of day, not the part the hub moved it to, and a lighter week no longer shortens the session.
- **Stadig Macro**'s automatic Log hours no longer follow the hub's wake and bed: they run from 7 AM to the hour before the caffeine bedtime set in Stadig Macro, or to 8 PM without one.

`AppID.hub` stays a case, so a profile or an envelope the hub wrote still decodes, and so does `TrainingPriority.Source.hub` in a block saved with one of its priorities. `LegacyDataTests` in `SystemStore` covers it.

## What Stadig Mind left behind

Its files are left unread and untouched. `AppID.knowledge`, `StatKind.intelligence` and `.wisdom` and `SessionKind.study` are still cases, so a profile or a life mode it wrote decodes as before (`LegacyDataTests` in `SystemStore`).

## Between devices

The App Group only reaches the apps on one device. `FamilySync` (`SystemStore`) mirrors every file in the container into the family's CloudKit database, `iCloud.dev.svindland.stadig`, which both apps list beside their own, and writes newer copies from other devices back. Newest wins by the envelope's `writtenAt`, and a file on disk at a newer schema than the incoming copy is never replaced. It carries files by path, not by key, so the hub's and Stadig Mind's files travel like any other. Deletes aren't carried; the files that need them (life modes) keep tombstones inside.

## Changing a payload

The apps ship on their own schedules, so what one writes the other must still read, and so must the copy of either app someone hasn't updated.

- An optional field with a default needs no bump: older readers skip it. That's how `NutritionSummary.fast` was added.
- Anything else is a schema version bump on the key, a `migrate` step on the `SharedKey`, and a migration test. A reader never overwrites a file at a newer schema than it knows.
- `ContractTests` in `SystemCore` hold each payload in the shape the apps write today.
- Dates are whole milliseconds since 1970 (`SystemJSON`). Stamp in whole seconds: a date that doesn't come back the same looks like a change on every read.

## Stats

There are six: Strength, Physique, Endurance, Agility and Discipline from Stadig Lift, Vitality and Discipline from Stadig Macro. Each app publishes its own as `StatReading`s in its summary. There's no overall level.

The rule is that each app shows its own stats, and once both apps are set up each shows all six, labelled with the app that decides each one. The merging is `StatsBoard` in `SystemCore`, so both apps give the same answer, and `SystemStore` reads it from the container:

- `StatsBoard.lines(shared:today:timeZone:)` (`SystemStore`) reads both summaries from the container and returns a `StatLine` for each of `StatsBoard.shown`, in the same order every time. `StatsBoard.lines(lift:macro:today:timeZone:)` (`SystemCore`) is the same from summaries in hand, which is how Stadig Lift passes its own before it's written.
- `StatLine.apps` says which app a stat comes from: Stadig Lift, Stadig Macro or both. `sources` has each app's own number and label. `app` is the one that would decide it before anything is published. A stat both publish (Discipline) is the average of their scores and the worse of their trends.
- `StatsBoard.bothApps(shared:today:timeZone:)` (or `bothApps(lift:macro:…)`) says whether both are publishing.
- A summary older than 28 days (`StatsBoard.staleDays`) counts as nothing, and a summary from any other app is ignored, so Intelligence and Wisdom never show.

### How each has moved

Each app records its own scores as it publishes them, and publishes the history they make in `apps/<app>/scores.json` beside its summary: a `ScoreHistory` (`SystemCore`), one reading a day for each stat (the day's last, to a tenth), every one for the last nine weeks, then each week's and each month's last, and the first, for two years.

- **The app's own store keeps them, a record a day** (`ScoreDayRecord` in `SystemStore`, kind `score-day`, its id from the day), so they reach the person's other devices through the app's own CloudKit container a day at a time: what two devices recorded adds up, and a reinstall gets every day back. `RecordStore.recordScores(_:app:on:now:)` saves the day's record when its scores change and returns the history all the records make; the records are all kept (a few dozen bytes a day) and only the published history is thinned.
- **The file is drawn from the store**, written when the history changes. `FamilySync` carries it like any other file, newest wins, so a device whose store hasn't caught up can briefly publish fewer days; it writes the rest when they arrive, and no app answers another device's copy with its own, so the two never take turns.
- `StatsBoard.lines(shared:today:)` reads both apps' histories with their summaries, and each `StatLine` carries `change`, how far it moved this month (`ScoreChange`), or nil with nothing to measure from. `StatLine.change(over:today:)` measures any `ScoreWindow`: `.month` ("+2 this month", since this date last month), `.since(month:)` ("+3 since August", from the score as that month began) or `.sinceCheckIn` ("since the last check-in"). Under a point either way is steady. A stat both apps publish moves by the average of their changes.
- `StatsBoard.lookBack(today:)` is the three-month window Body's Physique uses, and `StatsBoard.earlier(_:today:)` Your shape's dashed outline from it.
- It's a file of its own rather than a field of `AppSummary` because every copy of either app rewrites its summary, and an older one would drop the field each time; nothing but this version writes `scores.json`. `AppSummary` and its schema are unchanged. An app that records no history (an older copy) just shows no change for its scores.

`StatsBoardTests`, `ScoreHistoryTests` and `ContractTests` (`SystemCore`), `SharedStatsTests` and `LegacyDataTests` (`SystemStore`) cover it.
