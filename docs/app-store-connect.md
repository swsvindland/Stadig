# App Store Connect

How Stadig Lift and Stadig Macro are set up on the store. [ci-cd.md](ci-cd.md) covers builds, Xcode Cloud and cutting a release; the listing's text as entered is in [Store/listing.md](../Store/listing.md).

## What's there

| | Stadig Lift | Stadig Macro |
|---|---|---|
| App Store | [apps.apple.com/app/stadig-lift/id6824198193](https://apps.apple.com/app/stadig-lift/id6824198193) | [apps.apple.com/app/stadig-macro/id6824204323](https://apps.apple.com/app/stadig-macro/id6824204323) |
| Bundle id | `dev.svindland.stadig.lift` | `dev.svindland.stadig.macro` |
| Versions | iOS (with the Watch app), macOS and visionOS, one record | the same |
| Price | Free, in all 175 countries or regions | the same |
| In-app purchases and subscriptions | None | None |
| Privacy Policy URL | `https://stadig.dev/privacy` | the same |
| App Privacy | Data Not Collected | the same |
| Support URL | `https://stadig.dev/support` | the same |

Stadig Lift 1.0 and Stadig Macro 1.0 were released on iOS on 2026-11-18. What was checked for each release, and what App Review asked, is in [agent-docs/verification.md](../agent-docs/verification.md) and `Store/listing.md`.

`main` builds 1.1 of both apps since 2026-11-25. It stayed at 1.0 for a week after the release, and App Store Connect takes no new builds of a version once it's approved, so `main`'s archives from the iOS approval on 2026-11-18 to then didn't reach TestFlight. The macOS and visionOS 1.0 versions, still rejected, can't get a build from `main` now: change their version number to 1.1 in App Store Connect, or build them from a `release/<app>-1.0` branch.

## Both apps are free

Since 2026-11-11. Purchases are off in the code (`enabled: false` in each app's `Purchase/Purchases.swift`): `SystemPurchases` then counts everything as owned and never shows an offer. On 2026-11-13 both apps' price was set to Free everywhere. Neither record had a purchase or subscription product, so there was nothing to remove from sale.

So a new version needs nothing from this page beyond the listing.

## Before a build reaches people

Each of these stops a build or a sync, and none of them shows up in a local build.

- **A new target's bundle id.** Xcode Cloud's automatic signing can't register an id or turn on a capability. Register it on developer.apple.com with iCloud and the App Group, or archive once in Xcode ([ci-cd.md](ci-cd.md) has the detail).
- **The CloudKit schema.** A change to what an app stores has to be deployed to Production for its container in the CloudKit Console, or App Store builds won't sync.
- **`stadig.dev`** has to be up: the listing's privacy and support links point at it.
- **The calls waiting for sign-off** that the release would ship: [agent-docs/decisions.md](../agent-docs/decisions.md).

## If a price comes back

The code for it is still linked: the `SystemPurchases` package, each app's `.storekit` file for local testing, and the product ids in [architecture.md](architecture.md#identifiers). The apps were built to sell as a free download with 21 free days, then a one-time purchase or a monthly subscription.

What that takes on the store's side:

- The Paid Apps Agreement, a bank account and the tax forms, once for the account.
- A non-consumable and a subscription group per app, with exactly the product ids the code reads. An id can't be changed once it's made.
- A first purchase and a first subscription each have to be submitted with a new app version.
- Prices need no build: the apps show what the App Store says. The site names no price, so one would go in `Site/src/content/site.ts` and the `offers` in the JSON-LD.

The step-by-step runbook written for that model, with the fields to enter, the note for App Review and the list to test on a device, was this page until the repository was tidied to go public. It's in git: `git show aa3ad07:docs/app-store-connect.md`.
