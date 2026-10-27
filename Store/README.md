# App Store screenshots

The screenshots for Stadig Lift, Stadig Macro and Stadig Mind, kept as [storeassets](https://github.com/swsvindland/screenshot) projects: the raw captures, the captions and the brand, which storeassets frames into every size App Store Connect asks for. One project per app for the iPhone and iPad, and one for each Watch app (a storeassets slot renders for every size its project has, and the Watch set is its own few screens).

| Project | Sizes | Screens |
| --- | --- | --- |
| `lift` | iPhone 6.9" (1320×2868), iPad 13" (2064×2752) | session, today, plan (Program on the iPad), progress, body |
| `lift-watch` | Apple Watch (422×514) | set, rating, rest, conditioning, home |
| `macro` | iPhone 6.9", iPad 13" | today, search, scan, plan, progress, meal prep |
| `macro-watch` | Apple Watch | today, log again, water, supplements, weigh-in |
| `mind` | iPhone 6.9", iPad 13" | plan, japanese, maths, progress, shelf |

App Store Connect scales the 6.9" set down for smaller iPhones and the 13" set for smaller iPads. Mac and Vision Pro screenshots aren't here yet.

## Recapturing

After a change to a screen that's in the set:

```sh
Scripts/store-screenshots.sh lift          # or macro, mind; all three by default
```

It runs the app's `StoreScreenshots` UI test (`Apps/<App>/UITests/StoreScreenshots.swift`) on a Pro Max iPhone and a 13-inch iPad Pro at once, over `-seedSampleData`, and the Watch app on an Apple Watch Ultra 3 with its sample launch arguments, then imports every capture into the project, replacing the old one by name. The simulators are this checkout's own ("Stadig Shots iPhone|iPad|Watch <checkout>"), light mode, 9:41. The test skips itself in every other run, so the UI test plans carry it without running it.

Stadig Mind's Today isn't in the set: on a rest day it says so, and which day is a rest day depends on when the screenshots are taken.

## Framing, checking and exporting

storeassets isn't a dependency of the apps; install it once (`cargo install --locked --git https://github.com/swsvindland/screenshot storeassets-cli`) or point `STOREASSETS` at a build.

```sh
storeassets -C Store/lift preview --open     # contact sheets and an HTML gallery in .storeassets/preview/
storeassets -C Store/lift validate           # exit code 2 if App Store Connect would refuse something
storeassets -C Store/lift export             # .storeassets/exports/folders/apple/en-US/<size>/NN-<slot>.png
```

Upload the exported PNGs in App Store Connect, in their numbered order, under the version's iPhone 6.9", iPad 13" and Apple Watch screenshots. Captions live in `copy/en-US.json`; change one with `storeassets -C Store/lift copy set session.headline "…"` (`**word**` is drawn in the accent colour), then preview again.

Renders, previews and exports are git-ignored; captures, captions and the brand are committed.
