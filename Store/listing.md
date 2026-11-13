# App Store listing text

What's entered in App Store Connect for each app's 1.0, English (U.S.), as of 2026-11-13. Each app has three 1.0 versions, iOS (with the Watch app), macOS and visionOS, and all three carry the same text below; screenshots differ per platform (`Store/README.md`). App Store Connect is the source of truth; change it there and here together. The copy comes from the site (`Site/src/content/site.ts`), so a claim that changes there changes here too. Limits: subtitle 30 characters, promotional text 170, keywords 100, description 4,000.

Both apps share these:

| Field | Value |
| --- | --- |
| Price | Free, all 175 countries or regions |
| Category | Health & Fitness (Lift's second: Sports; Macro's: Food & Drink) |
| Age rating | 9+ (12+ in Brazil and Vietnam): every content question None or No, except "Health or Wellness Topics", Yes |
| Regulated medical device | No |
| Privacy Policy URL | https://stadig.dev/privacy |
| App Privacy | Data Not Collected (saved, waiting to be published) |
| Support URL | https://stadig.dev/support (the site's support form, which files a GitHub issue; every page's footer has the email) |
| Copyright | 2026 Sam Svindland |
| Sign-in required | No |
| Release | Manually, after approval |

## Stadig Lift

- **Subtitle:** Strength training that adapts
- **Marketing URL:** https://stadig.dev/lift
- **Content rights:** no third-party content (the exercise library taken as our own; see `docs/decisions.md`)
- **Promotional text:** Your program, written for you. Every set filled in and adjusted to how the last one felt. Free, with no account and no ads, and it works offline.
- **Keywords:** `workout,gym,weightlifting,RPE,progressive overload,deload,program,planner,powerlifting,log,tracker`

**Description:**

```text
Stadig Lift writes your strength program, sets every weight, and adjusts each set to how the last one felt. Most training apps are notebooks: you decide what to do and they remember it. Stadig Lift decides.

ONE TAP A SET
Every set comes filled in: the weight, the reps, the plates a side. Lift it, then tap how it went: Easy, Just right or Missed. The next set adjusts, and your rest starts by itself.

A PROGRAM THAT WRITES ITSELF
• Set up once: your days, your time, your equipment and what you want from training.
• A short assessment block finds your real numbers and calibrates your effort ratings. Experienced lifters finish it early.
• Then one block, not a menu, with a Why if you want it. Five weeks and a deload by default, shorter in a cut, longer in a bulk.
• Short on time? Tap 30 or 45 minutes and today's session fits.

IT LEARNS WHETHER TO BELIEVE YOU
Everyone misjudges reps in reserve. Stadig Lift starts from your experience and rebuilds its trust in your ratings from evidence: a rep-out after a rated set shows the truth, and a heavier later set proves more was left.

A FATIGUE BUDGET
Every set has a cost, and so do runs, classes and workouts from Apple Health. Sleep, HRV, resting heart rate, soreness and stress feed the budget. When the signals stack, the deload comes early. Vacation, crunch, injury and illness modes change the plan instead of breaking it.

SCORES THAT MOVE ON REAL TESTS
Strength against bodyweight standards, Endurance from VO₂ max and resting heart rate, Agility from five mobility tests, Physique from the tape, and Discipline from four weeks of the plan kept. Opening the app moves nothing, and each score names what's holding it back.

ON YOUR WRIST
The Apple Watch app logs and rates sets, times rest by heart rate, ending it early once you've recovered, and runs conditioning by zone. A Live Activity holds the rest timer on your iPhone.

ON EVERY SCREEN
iPhone for the gym floor. On iPad, the Mac and Apple Vision Pro, Stadig Lift lays out your whole program and the exercise library. Everything syncs through your own iCloud.

BETTER WITH STADIG MACRO
Stadig Macro learns your real maintenance and picks your phase. Use both, and a cut shortens the block and reads a stall as expected, a bulk lengthens it, and both apps show all six scores.

FREE, PRIVATE, OFFLINE
Stadig Lift is free, all of it. No account, no ads, no analytics and no third-party code. The exercise library ships inside the app, so it works in a basement gym. Your data stays on your devices and in your iCloud. Export to CSV and back up whenever you like.

Stadig is Norwegian for steady.
```

**App Review notes:**

```text
Stadig Lift is free, with no account, no sign-in and no in-app purchases. Everything works from the first launch.

Onboarding asks for training days, session length, equipment, experience and goals, then writes the first session of a short assessment block. Each set is logged with one tap (Easy, Just right or Missed).

Apple Health access is optional; the app works without it. The Apple Watch app is optional and mirrors the current session. Data stays on the device and in the person's private iCloud database (CloudKit). Nothing is sent to us, and there are no analytics or third-party SDKs.
```

## Stadig Macro

- **Subtitle:** Macros that adapt every week
- **Marketing URL:** https://stadig.dev/macro
- **Content rights:** contains third-party content, with the rights (USDA is public domain, Open Food Facts is ODbL, the NIH label database is public); the description ends with the credit
- **Promotional text:** Learns your real maintenance from your weigh-ins and adjusts your targets every week. Log with one tap, a few letters, a scan or a photo. Free, no account, no ads.
- **Keywords:** `calorie,counter,tracker,TDEE,maintenance,nutrition,food,diet,barcode,scanner,protein,cut,bulk,log`

**Description:**

```text
Stadig Macro works out your real maintenance from what you eat and weigh, recommends one phase, and moves your targets a little every week. Calorie counting fails for two reasons: the target is a guess, and logging is a chore. Stadig Macro fixes both.

LOGGING IN A TAP
• Today shows what you usually eat around now. One tap logs it at your usual amount.
• Type "chick 200" and press Return: roasted chicken breast, 200 g, logged. Type "2 eggs, toast, coffee" and all three are logged, with one Undo.
• Scan a barcode, or hold the camera on a Nutrition Facts label and it reads line by line as you pan.
• Take a photo or say what you ate. Apple's on-device model names the foods and amounts; the nutrients always come from the catalog, never from a guess.
• From 5 PM, What fits tonight suggests the foods you usually eat that fit what's left, ranked by the protein they cover.

YOUR MAINTENANCE, MEASURED
Log for a couple of weeks and weigh in daily. A smoothed weight trend against what you ate on complete days gives your real maintenance. Weekly check-ins move it a third of the way and cap any change at 150 kcal, so one bad weigh-in can't swing your week.

ONE PHASE, WITH REASONS
Cut, bulk, maintenance, recomp or a diet break. Stadig Macro recommends one and says why, from your trend, your strength and how long you've been dieting. You can pick another.

MORE THAN MACROS
• Food quality: the ultra-processed share of your calories, and fermented foods by the day.
• Meal prep: a week of prep-friendly meals sized to your targets, with the grocery list and a timed prep day.
• Supplements: scan a bottle and its label comes from the NIH database, offline, with upper-limit warnings.
• Water, coffee and caffeine, if you want them.

WITHOUT OPENING THE APP
Siri, Shortcuts, widgets with buttons, Controls and the Action Button all log. On Apple Watch, see calories left at a glance and log your usual with Log Again.

ON EVERY SCREEN
iPhone for the day. On iPad, the Mac and Apple Vision Pro, compare foods and plan the week. Everything syncs through your own iCloud, and food and weigh-ins go to Apple Health if you like.

BETTER WITH STADIG LIFT
Stadig Lift writes your training program around the phase Stadig Macro picks. Use both, and your steps are read before calories are cut, life modes are shared, and both apps show all six scores.

FREE, PRIVATE, OFFLINE
Stadig Macro is free, all of it. No account, no ads, no analytics and no third-party code. The food, supplement and drink catalogs ship inside the app and work offline. Your data stays on your devices and in your iCloud. Export to CSV and back up whenever you like.

Food data from USDA FoodData Central, Open Food Facts (ODbL) and the NIH Dietary Supplement Label Database.
```

**App Review notes:**

```text
Stadig Macro is free, with no account, no sign-in and no in-app purchases. Everything works from the first launch.

Onboarding asks a few questions about the person and their goal, then opens Today, where food is logged with a tap, by typing (for example "chick 200" and Return), by barcode or label scan, or from a photo or a spoken sentence.

Photo, label and voice logging use Apple's Foundation Models framework; the nutrients always come from the food catalogs that ship inside the app (USDA, Open Food Facts and the NIH supplement database). Camera and Apple Health access are optional. Data stays on the device and in the person's private iCloud database (CloudKit). Nothing is sent to us, and there are no analytics or third-party SDKs.
```
