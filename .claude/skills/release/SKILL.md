---
name: release
description: Cut a release of Stadig Lift, Stadig Macro or Stadig Mind to TestFlight and the App Store: version bump, release branch, pre-release checks and what Xcode Cloud does. Use when asked to ship, release, submit for review, bump a version, or prepare a TestFlight build for external testers.
---

# Release an app

Internal TestFlight builds need nothing: every push to `main` that touches an app archives it to TestFlight (Xcode Cloud's Main workflow). This is for a version going to external testers and the App Store. Full background: `docs/ci-cd.md`.

## Before cutting the branch

- `main` is green: GitHub `CI` passed on the commit, and the app's Xcode Cloud Main build passed (ask the owner if you can't see it).
- `docs/verification.md`: what's verified on a device, and what isn't. Raise anything unverified that the release depends on.
- `docs/decisions.md`: list the calls still waiting on sign-off that this release ships, for the owner to confirm.
- First release only: everything in `docs/app-store-connect.md`: the agreements, the app record, both products, and both attached to the version.
- Catalogs: the manifest's release holds the catalogs this version should ship (`Scripts/catalogs.manifest`).
- Privacy strings: every Info.plist usage description (in the generator) still says truthfully what the app does.
- Screenshots: if a screen in the store set changed, `Scripts/store-screenshots.sh <app>`, then `storeassets -C Store/<app> validate` and `export` (and `Store/<app>-watch` for Stadig Lift and Stadig Macro); the owner uploads them in App Store Connect. `Store/README.md`.

## Cut it

```sh
git switch -c release/lift-1.1 main          # macro-…, mind-…
# Scripts/generate-project.py: VERSIONS["LiftTrack"] = "1.1"
python3 Scripts/generate-project.py
Scripts/build.sh lint && Scripts/build.sh unit lift && Scripts/build.sh ui lift
git commit -am "Stadig Lift 1.1"              # in a worktree; in the shared checkout use the commit skill
```

Then on `main`, bump `VERSIONS["LiftTrack"]` to the next version ("1.2") and commit: TestFlight rejects builds of an already-approved version, so `main`'s internal builds must always be ahead of what shipped.

A release-branch archive with `enabled: false` in the app's `Purchase/Purchases.swift` fails on purpose in `ci_pre_xcodebuild.sh`; that's the guard against shipping the paid app unlocked.

Push only when the owner says to. The push starts the app's Release workflow: package tests, both test plans, archive, upload to TestFlight for the external group. The owner submits it for review in App Store Connect.

## After

- Fixes for the release go on the release branch first, then get merged back to `main`.
- When it's live: tag the shipped commit (`git tag lift-v1.1`), merge the release branch into `main`, and note the version in `docs/verification.md`.
- Versions only go up; build numbers are Xcode Cloud's and never need touching.
