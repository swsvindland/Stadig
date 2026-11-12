# Design: Steady Instrument

How Stadig Lift and Stadig Macro look, and why. The designs themselves live on the design canvas, [Stadig Lift & Macro — App Design](https://claude.ai/artifact/1zfrqpAQZbM8fXvoCn23wT): every screen, a clickable prototype of adding food, a concept per device, and the marketing site.

## The look

- **Ink and paper.** An ink ground in dark mode and warm paper in light; the apps follow the system appearance. Cards are a quiet surface on the ground with continuous 22-point corners. Vision Pro keeps the system's glass instead of an opaque ground.
- **Numbers are the hero.** Every screen has one number that answers its question (kcal left, the weight on the bar, a score), set big, heavy, tabular and tightly tracked. Units sit beside it, smaller and grey. Labels over numbers are small uppercase eyebrows.
- **One gauge: the ruler.** Calories, macros, scores, rest, a session's progress and a block's weeks are all a fill on a track, ticked every tenth so it reads as an instrument. No rings, no donuts.
- **One accent per app.** Stadig Lift is ultramarine (#6D8BFF dark, #3355E0 light), Stadig Macro is leaf (#3ECF8E dark, #12804F light). Other colour only where it means something: protein, carbs and fat; Easy, Just right and Missed; which app measures a score.
- **Plain words, said once.** No mascots, streaks, confetti or upsell. Both apps are free and open source.

## Your shape

The six scores (Strength, Endurance, Agility, Vitality, Discipline, Physique, clockwise from the top) drawn as one hexagon whose spokes are rulers. It grows where the work is done. Each corner is coloured by the app that measures it (Lift, Macro, or both for Discipline), and a score nothing measures yet leaves its spoke dashed and the figure open. Each app shows its own scores; with both set up, both show all six. The numbers come from `StatsBoard.lines(shared:today:)` in `SystemStore`.

## Where it is in code

`Apps/<App>/iOS/Components/Stadig.swift`, the same file in both apps (there's no shared UI package, so change both together): the `Ink` palette, `.numeral(_:)`, `Measure`, `.eyebrow()`, `Ruler`, `.inkCard()`, `.inkGround()`, `SourceChip` and `ScoreShape`. Each app's accent is its asset catalog's `AccentColor`, in the app, its widgets and its Watch app. `Components/Theme.swift` maps the app's older names onto these.

## One job per device

What the canvas proposes for each device, beyond the iPhone screens. These are concepts: none of it is built yet.

| Device | Where the person is | Its job |
| --- | --- | --- |
| iPhone | At the rack, at the table; one hand | Capture: a set or a food in one gesture. Floor mode (the phone set down becomes one big button), StandBy and the Dynamic Island, "What fits?" in the evening |
| Watch | Phone in the locker or the other room | Confirm: Double Tap logs the set or the usual food, the Crown changes it, the face is the gauge |
| iPad | Propped where the work happens | Stay put and be readable: the gym scoreboard, counter mode for meal prep, the year on one axis |
| Mac | At a desk | Plan and review, and log without picking up the phone: the menu bar logger, the week desk, the program desk |
| Vision Pro | At home, hands full | Put the instrument where the work is: beside the rack, over the pots; your shape in the room |
