# App Store screenshots

The screenshots for Stadig Lift and Stadig Macro, kept as [storeassets](https://github.com/swsvindland/screenshot) projects: the raw captures, the captions and the brand, which storeassets frames into every size App Store Connect asks for. One project per app for the devices that show the same screens, and one for each set that differs (a storeassets slot renders for every size its project has): the Watch apps' few screens, and Stadig Macro on the Mac and Vision Pro, which have no label scan.

| Project | Sizes | Screens |
| --- | --- | --- |
| `lift` | iPhone 6.3" (1206×2622), iPhone 6.9" (1320×2868), iPad 13" (2064×2752), iPhone Duo outer (1398×2034) and inner (2853×2007), Mac (2880×1800), Vision Pro (3840×2160) | session, today, plan (Program on the iPad, the Mac and Vision Pro), progress, body |
| `lift-watch` | Apple Watch (422×514) | set, rating, rest, conditioning, home |
| `macro` | iPhone 6.3", iPhone 6.9", iPad 13", iPhone Duo outer and inner | today, log, search, scan, plan, progress, meal prep |
| `macro-mac-vision` | Mac, Vision Pro | today, log, search (Foods), plan, progress, meal prep |
| `macro-watch` | Apple Watch | today, log again, water, supplements, weigh-in |

Since late 2026 App Store Connect's required iPhone size is 6.3" ("iPhone with Dynamic Island, medium display"); 6.9" is optional. Both are rendered from the same Pro Max captures. App Store Connect scales the 13" set down for smaller iPads. The listing text that goes with them is in [listing.md](listing.md).

The iPhone Duo is one slot in App Store Connect, which takes either display's size, in either orientation, so each app has two sets to choose from: the outer (folded) and the inner (the app open across the unfolded phone, landscape as it's held). Stadig Macro's listing has the folded set, and Stadig Lift's has both, open first, ten in all (chosen 2026-11-13). Folded, the apps show their iPhone layouts; open, the inner display is regular width, so they show their wide ones (Stadig Macro's search and meal prep are Foods and Meal Plan, as on the iPad; Stadig Lift's plan slot stays Plan, as on the iPhone). The Mac and Vision Pro sets go under the app's macOS and visionOS versions. The Mac's window is framed as it is (its own title bar and corners) and Vision Pro's is shown in the simulator's room, cropped to the window and the room around it; neither gets a device frame.

## Recapturing

After a change to a screen that's in the set:

```sh
Scripts/store-screenshots.sh lift          # or macro; both by default
```

It runs the app's `StoreScreenshots` UI test (`Apps/<App>/UITests/StoreScreenshots.swift`) on a Pro Max iPhone and a 13-inch iPad Pro at once, over `-seedSampleData`, then on an iPhone Duo folded and unfolded; the Watch app on an Apple Watch Ultra 3 and the app on a Vision Pro (the 4K one, whose screenshots are 3840×2160) with their sample launch arguments; and the Mac app on this Mac, the same way. Then it imports every capture into its project, replacing the old one by name. The simulators are this checkout's own ("Stadig Shots iPhone|iPad|Watch|Duo|Vision <checkout>"), light mode, 9:41. The test skips itself in every other run, so the UI test plans carry it without running it. `DEVICES=duo,mac Scripts/store-screenshots.sh lift` recaptures only some devices (`iphone`, `ipad`, `watch`, `duo`, `mac`, `vision`; all by default).

- **iPhone Duo.** The simulator has no fold control without the Simulator app, so the script builds a small helper (`duo_fold`, into DerivedData) that runs on the simulator and asks SpringBoard to fold or unfold, as its own display tool does. XCTest's main screen stays the outer display when the phone is open, so on the Duo the test asks the script for each screenshot (a `<name>.wanted` file beside it) and the script takes it from the display the app is on (`simctl io --display`). The test's class folder comes from `STORE_CLASS` (`foldable-outer`, `foldable-inner`).
- **Vision Pro.** Each screen is a launch (`-tab program -programLift barbell-bench-press`, `-startSession -sessionAt set`, …), a screenshot of the room after 14 seconds, and a crop to its middle 70% (still 16:9), where the window opens at its default size.
- **Mac.** Each screen is the app launched in the background with `-NSRequiresAquaSystemAppearance YES` (light, whatever the Mac's appearance), its window captured (`screencapture -l`) and the app quit; the window is in its inactive state, since it never comes to the front. It needs Screen Recording for the terminal. The window is found, and the app quit, by the launched copy's process, so a copy of the app already open (the App Store's or TestFlight's, with the same bundle id and window name) is left alone. The windows are their default sizes: Stadig Lift 1240×820 points, its session window 1080×760, Stadig Macro 1280×820.

Stadig Macro's run at any hour: the script launches it in a whole-hour time zone where it's 1 PM (`STORE_TZ`, Etc/GMT±N), and its Today slot seeds the day so far as yesterday went (`-seedToday`), so it shows breakfast and lunch rather than "0 of 2,200 kcal" before breakfast. Its Log slot is yesterday, which looks the same at any hour. On the Mac and Vision Pro every screen seeds today the same way, since their sidebar shows the calories left.


## Framing, checking and exporting

storeassets isn't a dependency of the apps; install it once (`cargo install --locked --git https://github.com/swsvindland/screenshot storeassets-cli`) or point `STOREASSETS` at a build. It needs a build with the `foldable-outer` and `foldable-inner` device classes (the iPhone Duo's displays' own captures, from 2026-11-13); an older one can't read these projects. The `stadig` and `stadig-full` templates (`templates/`, the same in every project) lay out landscape canvases: the iPhone Duo open with the words over the device, and the Mac and Vision Pro with the window whole and unframed under them.

```sh
storeassets -C Store/lift preview --open     # contact sheets and an HTML gallery in .storeassets/preview/
storeassets -C Store/lift validate           # exit code 2 if App Store Connect would refuse something
storeassets -C Store/lift export             # .storeassets/exports/folders/apple/en-US/<size>/NN-<slot>.png
```

Upload the exported PNGs in App Store Connect, in their numbered order, under the version's Media Manager: iPhone 6.3" (required) and 6.9" (optional), iPad 13", iPhone Duo (either set) and Apple Watch under iOS, then Mac and Vision Pro under the macOS and visionOS versions. The upload is by hand: drag each folder onto its slot; `Store/upload/<App>/` (git-ignored) holds them numbered in that order. Captions live in `copy/en-US.json`; change one with `storeassets -C Store/lift copy set session.headline "…"` (`**word**` is drawn in the accent colour), then preview again.

Renders, previews and exports are git-ignored; captures, captions and the brand are committed.
