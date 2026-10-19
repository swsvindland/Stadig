---
name: run-app
description: Launch Lift Track, Macro Track or Mind Track in the iOS Simulator with seeded data or on a specific screen, take screenshots and drive it, without touching anyone's stored data. Use to see a change working in the real app, check a screen, or reproduce a bug.
---

# Run an app in the simulator (or on the Mac)

Every app runs on iPhone, iPad, the Mac and Vision Pro. Check a regular-width (desktop) layout on the iPad simulator (`Scripts/build.sh simulator ipad`) or the Mac; Vision Pro's is `Scripts/build.sh simulator vision`, installed and launched the same way.

## Build and install

```sh
Scripts/build.sh ios          # or macro / mind: builds for this checkout's own simulator
UDID=$(Scripts/build.sh simulator)
xcrun simctl boot $UDID 2>/dev/null; open -a Simulator
xcrun simctl install $UDID "$(Scripts/build.sh products)/LiftTrack.app"
```

Use your own simulator, by UDID. Other sessions use the iPhone 18 Pro, iPhone 18 Pro Max and iPhone 17e simulators; installing there replaces their build. If you must use a shared one, say so.

## Launch

Bundle ids: `dev.svindland.stadig.lift`, `dev.svindland.stadig.macro`, `dev.svindland.stadig.mind`.

```sh
xcrun simctl launch --terminate-running-process $UDID dev.svindland.stadig.lift -inMemoryStore -seedSampleData -tab plan
```

- `-inMemoryStore` keeps nothing and never touches the stored data: use it unless the task is about persistence.
- `-seedSampleData` fills the store through the real engines (weeks of sessions, logging or study).
- `-uiTesting` is what UI tests use: in-memory store, no permission prompts, no animations.
- Each app has many more (open a tab, a logger, a session, a check-in, a sheet). They're listed in `docs/lift-track.md`, `docs/macro-track.md` and `docs/mind-track.md` under "DEBUG launch arguments", and parsed in each app's `iOS/App/*App.swift`.

## Look and drive

- Screenshot without the simulator panel: `xcrun simctl io $UDID screenshot /tmp/shot.png`, then read the PNG.
- Fatal errors and logs: `xcrun simctl launch --console-pty $UDID <bundle id> <args>`, or `xcrun simctl spawn $UDID log stream --predicate 'subsystem BEGINSWITH "dev.svindland.stadig"'`.
- Deep links: `xcrun simctl openurl $UDID 'macrotrack://log'` (the schemes are in the README's identifiers table).
- With the simulator tool: SwiftUI toggles need a held tap (`duration: 0.15`); screenshots lag taps by a second or two, so take a second one before deciding a tap failed.
- No camera in the simulator: Macro Track's `-liveScanDemo` and `-photo <file in Documents>`, and Mind Track's `-readImage <file>`, stand in for it.

## On the Mac

```sh
Scripts/build.sh mac lift     # signed ad hoc: runs on this Mac, keeps its data here ("This device only")
open -g -n "$(Scripts/build.sh products mac)/LiftTrack.app" --args -inMemoryStore -seedSampleData
swift Scripts/window-shot.swift "Lift Track" /tmp/mac.png    # just the app's window
osascript -e 'quit app id "dev.svindland.stadig.lift"'   # by bundle id: the app's name doesn't reach a debug build
```

The same launch arguments work. The Mac app is on the person's screen while it runs: launch it in the background (`-g`), capture only its window, and quit it when done.

When you report what you saw, say which simulator (or the Mac), which launch arguments, and attach the screenshot.
