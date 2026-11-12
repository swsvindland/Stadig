# App Store Connect: purchases and release

> **Both apps are free (since 2026-11-11).** Purchases are off in the code (`enabled: false` in each app's `Purchase/Purchases.swift`), so nothing below is needed for a new version. What's left for you in App Store Connect: set both apps' price to free, and for the products already made (the one-time purchase and the monthly subscription per app), remove them from sale. Nothing in the apps checks them now. The steps below are kept as the record of how it was set up.

Everything here happens on the App Store Connect website, once per app unless it says otherwise. The code side is done: each app reads these products by the ids below, and shows whatever prices you set here. [ci-cd.md](ci-cd.md) covers builds and Xcode Cloud; this covers what to sell and how to get it approved.

**How each app is sold:** a free download. 21 free days with nothing to sign up for, then $29.99 once or $2.99 a month. After the 21 days the app asks when opened, and "Just one more day" holds that off for a day, as often as someone likes.

## 1. Before anything else (once, for the account)

The Account Holder has to do these. Nothing paid can be sold or tested without the first one.

1. **Business → Agreements:** accept the **Paid Apps Agreement**, and any updated Developer Program License Agreement waiting there.
2. **Business → the same agreement:** add a **bank account** and complete the **tax forms** (the US form, at least). The agreement shows as Active once these are in.
3. **Small Business Program:** enroll at developer.apple.com/app-store/small-business-program. Apple then takes 15% instead of 30%, on purchases and subscriptions alike, while proceeds stay under $1 million a year. It isn't automatic, so apply before the first sale.

Proceeds at 15%: about $25.49 per $29.99 purchase and $2.54 per month of subscription, before tax.

## 2. The app records (once per app)

**Apps → + → New App**, or check they're already there from TestFlight:

| | Stadig Lift | Stadig Macro |
|---|---|---|
| Bundle id | `dev.svindland.stadig.lift` | `dev.svindland.stadig.macro` |

- **Platforms:** add macOS and visionOS on each app's page (**Add Platform**), so one purchase covers every device.
- **Pricing and Availability:** the app itself is **Free**. The money is all in-app purchases.
- **App Privacy:** the policy URL is `https://stadig.dev/privacy`. The site has to be live at that address first, because the paywall links to it too.

## 3. The one-time purchase (once per app)

**The app → Monetization → In-App Purchases → +**

| Field | Stadig Lift | Stadig Macro |
|---|---|---|
| Type | Non-Consumable | Non-Consumable |
| Reference Name | `Stadig Lift unlock` | `Stadig Macro unlock` |
| Product ID | `dev.svindland.stadig.lift.unlock` | `dev.svindland.stadig.macro.unlock` |
| Display Name | `Stadig Lift` | `Stadig Macro` |
| Description | `Stadig Lift, yours for good.` | `Stadig Macro, yours for good.` |

Then, on the same page:

- **Availability:** all countries, or the ones you sell in. Leave it on for every platform.
- **Price Schedule:** United States, **$29.99**. Let Apple work out the other countries.
- **Family Sharing:** turn on. It can't be turned off again once it's on.
- **App Store Localization:** the display name and description above, English (U.S.).
- **Review Information:** a screenshot of the paywall (section 8 says how to get one) and the review note in section 7.
- Save. It should read **Ready to Submit**. **Missing Metadata** means a field is still empty.

A product id can't be changed once it's created, so copy them exactly. A typo means the app can't find the product, and the buy buttons stay off.

## 4. The subscription (once per app)

**The app → Monetization → Subscriptions → Subscription Groups → +**

1. **Group:** Reference Name `Stadig Lift` (or `Stadig Macro`). Under **Localization** add a group display name, the same name, English (U.S.). Each app has its own group.
2. **Subscription, in that group:**

| Field | Stadig Lift | Stadig Macro |
|---|---|---|
| Reference Name | `Stadig Lift monthly` | `Stadig Macro monthly` |
| Product ID | `dev.svindland.stadig.lift.monthly` | `dev.svindland.stadig.macro.monthly` |
| Duration | 1 Month | 1 Month |
| Display Name | `Stadig Lift Monthly` | `Stadig Macro Monthly` |
| Description | `All of Stadig Lift, month to month.` | `All of Stadig Macro, month to month.` |

3. **Subscription Prices:** United States, **$2.99**. Let Apple work out the rest.
4. **Availability:** as for the one-time purchase.
5. **Family Sharing:** turn on, as for the one-time purchase.
6. **Review Information:** the same screenshot and review note.
7. **Do not add an introductory offer.** The app's free days come before either option. App Store Connect has no 21-day length anyway (it goes 1 week, 2 weeks, 1 month), and a free month on top would give people 7 weeks free.

Should read **Ready to Submit**, as above.

## 5. App Store listing (once per app)

Apple rejects subscription apps that miss these, so check each one on the version page.

- **App Description:** end it with the plain terms, and a link to the terms of use. Something like:

  > Free for 21 days, with no account. After that, $29.99 once or $2.99 a month. The subscription renews monthly until cancelled at least 24 hours before the renewal, in your Apple Account's settings. Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

  That link is Apple's standard terms, which is what the paywall links to as well. If you upload a custom licence under App Information instead, change `LegalLinks.terms` in `Packages/SystemPurchases/Sources/SystemPurchases/PaywallView.swift` to match.
- **Privacy Policy URL:** `https://stadig.dev/privacy`, under App Privacy.
- **App Privacy answers:** the apps collect nothing on our side (purchases go through Apple, and data stays on the device and in the person's iCloud), so "Data Not Collected" looks right, but that's your declaration to make.

## 6. Attach the purchases to the first version

**A first in-app purchase and a first subscription each have to go in with a new app version, and this is easy to miss.** A subscription goes in together with its group.

1. Upload a build that contains the products' code (anything from this change on).
2. Add both products to the version's submission: from **In-App Purchases and Subscriptions** on the version's page if it shows that section, or from **Monetization**, choosing the version as you submit each one.
3. Submit the version. The purchases are reviewed with it.

After that, new purchases of the same kind can be submitted on their own, and prices can change at any time without a new build: the app shows what the App Store says.

## 7. The note for App Review

Paste this under **App Review Information → Notes** on the version, and in each product's Review Information. Attach the screenshot of the prompt from section 8 too, since a reviewer won't wait 21 days to see it:

> This app is a free download with no account. Onboarding ends with a choice: buy once, subscribe monthly, or "Free for 21 days". The free days are counted by the app, with no purchase and nothing to sign up for, and all features work during them. After 21 days the app asks the person to buy or subscribe when they open it. "Just one more day" dismisses that for a day and can be used every day: no feature is taken away, and the app never stops working. Logging, export and backup are free regardless. The monthly subscription has no App Store introductory offer, and pays for ongoing updates to the app and its content. A screenshot of the prompt is attached.

The app needs no login, so there's no demo account to give.

## 8. Test before submitting

A **TestFlight** build is the easy way: purchases there aren't really charged, and it needs no test account. A subscription renews every 24 hours whatever its length, for 6 renewals, then ends. To test on a faster clock, make a Sandbox Apple Account under Users and Access → Sandbox and use the Sandbox sign-in in Settings on a device in Developer Mode.

Walk this list on one app, on a real device. **Item 4 matters most: it couldn't be checked anywhere else.**

1. A fresh install ends onboarding on the offer, showing real prices from App Store Connect.
2. Buy once: the offer closes, and Settings says "Yours for good. Thank you."
3. Delete the app, reinstall, and tap Restore purchase: it comes back.
4. **Subscribe, cancel it, and come back the day after it would have renewed. Reopen the app: it should stop saying "Subscribed" and fall back to where the free days left it.** Apple's local test tools can't expire a subscription in a way StoreKit's live calls see, so this is the only real proof.
5. Subscribe, then buy once: it says the subscription is still running, with a Manage button. Check that Manage opens the right place.
6. Sign in to a second device on the same Apple Account: purchases and the free days both carry over.
7. Turn on Airplane Mode and open the offer: it says the App Store didn't answer, with Try Again, and Free for 21 days still works.
8. On an iPad and the Mac, open the offer. A DEBUG build shows the prompt straight away with `-access lapsed`; see each app's doc for the launch arguments.

**The screenshots for Review Information:** on a simulator, launch a DEBUG build with `-uiTesting -seedSampleData -access undecided` for the offer, and `-access lapsed` for the prompt on opening. Both show sample prices at the amounts above. If you change the prices, take them on a TestFlight build instead, so they match.

## 9. Things that may still be in the way

These were true when last checked in October. Check them before the first release: each one stops a build or a sync, not just a purchase.

- **Watch bundle ids:** Xcode Cloud can't register `….watchkitapp` and `….watchkitapp.widgets` for Stadig Lift and Stadig Macro, so their archives failed. Register them with iCloud and the App Group on developer.apple.com, or archive once in Xcode. [ci-cd.md](ci-cd.md) has the detail.
- **CloudKit schema:** deploy each container's schema to Production in the CloudKit Console, or App Store builds won't sync. That includes the free days, which is what makes a second device agree.
- **GitHub Actions** wasn't starting jobs (a billing problem), so a red CI there meant nothing ran.
- **`stadig.dev`** has to be live for the paywall's Privacy Policy link.
- **`docs/decisions.md`** lists product calls waiting for your sign-off that this release would ship.

## If App Review turns down the free days

This is the most likely rejection. Apple's guideline 3.1.1 describes one way to offer a time-based free trial in an app without a subscription: a non-consumable in-app purchase at Tier 0 (free), named like "21-day Trial". Our free days don't use one, because you wanted no store sheet and nothing to sign up for, and apps tracking their own trials have been rejected before, with wording like "offers a free trial without implementing the offer in App Store Connect". Those reports are old and were about subscriptions, and our case is different, since nothing ever locks. It may pass, and the review note above is written to make that argument. The app also never calls it a trial, on purpose.

If it's rejected on those grounds, reply in Resolution Center first: point out that no feature expires. If that fails, the fix is small:

1. For each app, create a non-consumable: Reference Name `Stadig Lift 21-day Trial`, Product ID `dev.svindland.stadig.lift.trial`, Display Name `21-day Trial`, price **Free**.
2. Change `startFreeDays()` in `Packages/SystemPurchases` to buy it, and read the start date from its transaction.

"Free for 21 days" then shows Apple's sheet for $0.00, one tap with no signup, and the date comes from the App Store. The guideline says "non-subscription apps", and ours sell both, so whether that route is fully within the rule isn't certain, though one developer reported it approved beside a subscription.

## Changing a price later

Monetization → the product → Price Schedule. It needs no new build, because the app shows what the App Store says. Then update the prices on the site (`Site/src/content/site.ts`, `Site/src/pages/[app].astro`), and the `.storekit` files so local testing matches. The site states the prices in words; nothing else in the repo does.
