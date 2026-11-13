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

A score says how it has moved where the boards show it: "+2" in good, "steady" in the second grey and "−1" in ok beside a score in a row or a card (`ScoreChangeLabel`), and "+2 this month" or "+3 since August" as a tinted chip with its arrow beside a large one (`ScoreChangeChip`). Stadig Lift's Progress has the board's Month | Year (`InkSegmented`, 132 points wide) at its header's right, and its chip, the row under Strength and Your shape's rows say the year's change on Year ("+12 this year", or "+5 since October" when the scores began later). Your shape keeps the scores as the month three back began as a dashed outline behind the figure, named under it (`ShapeLegend`: "Now", "August"). Under a point either way is steady, and someone new sees nothing until there's a week to measure from ([shared-container.md](shared-container.md)).

## Where it is in code

`Apps/<App>/iOS/Components/Stadig.swift`, the same file in both apps (there's no shared UI package, so change both together): the `Ink` palette, `.numeral(_:)`, `Measure`, `.eyebrow()`, `Ruler`, `.inkCard()`, `.inkGround()`, `SourceChip`, `ScoreShape` with `ShapeLegend`, `ScoreChangeLabel` and `ScoreChangeChip`, and the page furniture both apps draw, so they read as one family:

- **Pages.** `PageHeader` (a tab's eyebrow over its 32-point `PageTitle`, round buttons beside it, 8 points under the status bar), and for a page pushed from a tab `DetailHeader` with `.detailPage(title:wide:)`: the eyebrow says where it was opened from, the bar keeps only its round back button so the edge swipe still goes back, and the tab bar goes. `CircleIconButton` (the 44-point `.ibtn`; `CircleIcon` is its face, for a `Menu`'s label). Onboarding's `StepBar` (back, a thin ruler, "2 of 9") and `StepHeading` (a 36-point question and what it's for).
- **Controls.** `InkButtonStyle`, as `.buttonStyle(.solid)` (the accent, for the one action) and `.ghost` (the raised grey), sized by the control size: 52 points `.large`, 44 regular, 34 `.small`. `.primaryAction()` and `.secondaryAction()` are those, and Vision Pro's own glass buttons there. `InkSegmented` (`.seg`), `Pill`. On Vision Pro's glass the raised grey and the card colour are black slabs, so a round button (`CircleIcon`), a chip and a segmented control's track take the system's material there, and the chosen segment a brighter wash of white (`ControlFill`).
- **Sheets.** One shape in both apps: `SheetBar` (the round close at the top left, a round button or small action at the right; on the Mac, which has no swipe, the close says what it does at the top right, Escape too, and the bar sits above the content rather than over it, `Platform.closesSheetsInWords` and `sheetChrome` in `Platform/Adaptive.swift`), the title large under an eyebrow saying where the sheet came from (`FormHeading` as a form's first section header, `SheetHeading` in a scrolling page), rows on cards under eyebrows, `InkSegmented` and `ChoiceChip` rather than the system's segmented control and capsules, the one action full width at the foot (`SheetFoot`), and Delete, Remove and End as ghost buttons under the cards (`FormActionRow`). `.inkSheet(bar:foot:)` puts them together; `.formPage(_:)` is a page pushed inside a sheet. `DetailHeader` dropped in as a list's row keeps clear of the corners an inset grouped list rounds each section's first and last rows to (which cut its eyebrow's first letter), on the ground with no separator.
- **Cards and rows.** `.card()` (22-point corners, 16 in) and `.tightCard()` (18, 14 in from the sides), `RowCard` (rows with hairlines, under an eyebrow) and `LinkRowLabel` (title, caption, value, chevron), `CardTitle` (`.h3` with a note at the right), `SectionEyebrow` (a group's eyebrow with a note at the right; a form's section headers are eyebrows too, and its rows sit on the card fill with `.inkRows()`), `ScaleLabel` (`.scale`), `SectionHeader`, `EmptyCard`.

Each app supplies what differs between them: `Ink.onAccent`, the ink on its own accent, and the `.pageBackground` and `.cardBackground` fills in `Components/Theme.swift`, and the platform helpers the pieces use in `Platform/Adaptive.swift`. Each app's accent is its asset catalog's `AccentColor`, in the app, its widgets and its Watch app. Widget extensions can't see the app's files, so each has a `WidgetInk.swift` with a commented copy of the palette, type and ruler it uses: change them with `Stadig.swift`. `Components/Theme.swift` maps the app's older names onto these.

## One job per device

What the canvas proposes for each device, beyond the iPhone screens. Built so far: Floor mode (Stadig Lift), the program desk (Stadig Lift's Program on the Mac and the iPad), the menu bar logger (Stadig Macro on the Mac), and the widgets, Live Activities, StandBy and complications on the new look. The rest are concepts.

| Device | Where the person is | Its job |
| --- | --- | --- |
| iPhone | At the rack, at the table; one hand | Capture: a set or a food in one gesture. Floor mode (the phone set down becomes one big button), StandBy and the Dynamic Island, "What fits?" in the evening |
| Watch | Phone in the locker or the other room | Confirm: Double Tap logs the set or the usual food, the Crown changes it, the face is the gauge |
| iPad | Propped where the work happens | Stay put and be readable: the gym scoreboard, counter mode for meal prep, the year on one axis |
| Mac | At a desk | Plan and review, and log without picking up the phone: the menu bar logger, the week desk, the program desk |
| Vision Pro | At home, hands full | Put the instrument where the work is: beside the rack, over the pots; your shape in the room |

StandBy is a desk view of its own, not the Lock Screen's or Home Screen's piece made bigger: Stadig Lift's rest and Stadig Macro's small widget are laid out on the design's StandBy board (an 844-point screen, a 334-point widget) and scaled to whatever the system gives them, so the number is as large as it fits (the countdown 232 points of 844, kcal left 108 of 334) and the words beside it small, read from across the room; the rest's ruler drains with the rest. On the Watch, the scores are the phone's: Stadig Lift's summary face leads with Strength, its change this month and Your shape as the phone's Progress has them, and Stadig Macro's Your Shape complication draws the six from what both apps publish.
