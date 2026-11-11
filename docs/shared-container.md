# The shared container

Stadig Lift and Stadig Macro each own their own database and publish small files for each other into the App Group container, `group.dev.svindland.stadig` (`SystemStore`'s `SharedContainer`). Each file is a versioned envelope, `{schemaVersion, writtenBy, writtenAt, payload}`, written atomically under file coordination, with a change notification the other app hears. The keys are the `SharedKey` extensions in `Packages/SystemStore/Sources/SystemStore/SharedContainer.swift`; the payload types are in `SystemCore`.

Stadig used to have two more apps: the hub (Stadig), which planned a day around work and showed the stats, and Stadig Mind. Both left this repo on 2026-11-11 (`docs/decisions.md`). What they wrote may still be on people's devices and in iCloud, so it's listed here too.

## The files

| File | Written by | Read by | What it is |
|---|---|---|---|
| `core/profile.json` | Stadig Lift, Stadig Macro (whichever is set up first, then either) | both, and Macro's Watch app | `SharedProfile`: setup answers asked once, training days and recurring classes |
| `core/life-modes.json` | both | both, and Macro's Watch app | `[LifeModePeriod]`: vacations, crunch and the rest, merged a period at a time with tombstones (schema 2; version 1 files decode as they are) |
| `core/calendar.json` | Stadig Lift | Stadig Macro and its Watch app | `SystemCalendar`: the current block, deloads and check-ins |
| `apps/liftTrack/summary.json` | Stadig Lift | Stadig Macro and its Watch app; the stats | `AppSummary`: stats, recent sessions, strength, fatigue, measurements, steps |
| `apps/macroTrack/summary.json` | Stadig Macro | the stats | `AppSummary`: stats |
| `apps/macroTrack/nutrition.json` | Stadig Macro | Stadig Lift | `NutritionSummary`: the phase, maintenance, day-by-day logging, a running fast |
| `apps/macroTrack/meals.json` | Stadig Macro | nothing in the apps now (`HubInputs` in `HubEngine` still reads it) | `MealRhythm`: the usual parts of the day for meals, and today's eaten ones |
| `hub/rhythm.json` | nothing now: the hub wrote it | Stadig Lift, Stadig Macro | `Rhythm`: the work pattern, wake and bed, clear evenings, the day's start, classes moved for good |
| `hub/changes.json` | nothing now: the hub wrote it | Stadig Lift | `[DayChange]`: out tonight, lighter weeks and one-day moves, with tombstones |
| `hub/recommendations.json` | nothing now, and the hub never did | Stadig Lift | `[Recommendation]`: priorities for another app's plan |
| `hub/quests.json` | nothing, ever | nothing | `[Quest]`: the key exists (`hubQuests`) and was never used |
| `apps/knowledge/summary.json`, `apps/knowledge/blocks.json` | nothing here: Stadig Mind wrote them | nothing | Its stats and its week of study blocks |

## What the hub left behind

The `hub/` files are frozen at whatever the hub last wrote, and they still count. Their payloads and schema versions are unchanged.

- **Stadig Lift** reads the rhythm for where a class was moved for good, and the changes for a one-day move (`RecurringActivity.part(on:rhythm:changes:)`, shown on Today) and for a lighter week, which caps the session at two thirds, to the nearest five minutes and no less than half an hour, without changing the weekly quota. A lighter week ends by itself on its Sunday.
- **Stadig Macro** reads the rhythm's wake and bed for the Log tab's automatic hours.
- No file means the app's own defaults, which is what anyone who never used the hub has.

Nothing can edit a rhythm or undo a weekly move any more. Whether the apps should go on honouring `hub/rhythm.json` is an open question in `docs/decisions.md`.

## What Stadig Mind left behind

Its files are left unread and untouched. `AppID.knowledge`, `StatKind.intelligence` and `.wisdom` and `SessionKind.study` are still cases, so a profile or a life mode it wrote decodes as before (`LegacyMindDataTests` in `HubEngine`).

## Between devices

The App Group only reaches the apps on one device. `FamilySync` (`SystemStore`) mirrors every file in the container into the family's CloudKit database, `iCloud.dev.svindland.stadig`, which both apps list beside their own, and writes newer copies from other devices back. Newest wins by the envelope's `writtenAt`, and a file on disk at a newer schema than the incoming copy is never replaced. It carries files by path, not by key, so the hub's and Stadig Mind's files travel like any other. Deletes aren't carried; the files that need them (life modes, day changes) keep tombstones inside.

## Changing a payload

The apps ship on their own schedules, so what one writes the other must still read, and so must the copy of either app someone hasn't updated.

- An optional field with a default needs no bump: older readers skip it. That's how `NutritionSummary.fast` and `Rhythm.placements` were added.
- Anything else is a schema version bump on the key, a `migrate` step on the `SharedKey`, and a migration test. A reader never overwrites a file at a newer schema than it knows.
- `ContractTests` in `SystemCore` hold each payload in the shape the apps write today.
- Dates are whole milliseconds since 1970 (`SystemJSON`). Stamp in whole seconds: a date that doesn't come back the same looks like a change on every read.

## Stats

There are six: Strength, Physique, Endurance, Agility and Discipline from Stadig Lift, Vitality and Discipline from Stadig Macro. Each app publishes its own as `StatReading`s in its summary. There's no overall level.

The rule is that each app shows its own stats, and once both apps are set up each shows all six, labelled with the app that decides each one. The screens for that aren't built yet. The logic is, in the `HubEngine` package, which both apps link (it kept its name when the hub left):

- `StatsBoard.lines(shared:today:timeZone:)` reads both summaries from the container and returns a `StatLine` for each of `StatsBoard.shown`, in the same order every time. `StatsBoard.lines(lift:macro:today:timeZone:)` is the same from summaries in hand.
- `StatLine.apps` says which app a stat comes from: Stadig Lift, Stadig Macro or both. `sources` has each app's own number and label. `app` is the one that would decide it before anything is published. A stat both publish (Discipline) is the average of their scores and the worse of their trends.
- `StatsBoard.bothApps(shared:today:timeZone:)` says whether both are publishing.
- A summary older than 28 days (`HubPlanner.staleDays`) counts as nothing, and a summary from any other app is ignored, so Intelligence and Wisdom never show.

`SharedStatsTests`, `StatsBoardTests` and `LegacyMindDataTests` cover it.

The rest of `HubEngine` is the hub's planner (`HubPlanner`, `ScheduleReader`, `HybridWeek`, `RhythmSummary` and the wording), still there with its tests and called by no app.
