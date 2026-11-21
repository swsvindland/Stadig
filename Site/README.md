# stadig.dev

The marketing site for Stadig (Stadig Lift and Stadig Macro). Astro, static output, zero client-side JavaScript, deployed on Vercel, with one Vercel function behind the support form.

```sh
pnpm install
pnpm dev        # http://localhost:4321
pnpm test       # the support form's function (Node's own test runner)
pnpm build      # dist/
pnpm preview
```

## The design

"Steady Instrument", the apps' own look: an ink ground, warm paper type, oversized numerals and tick rulers, one paper section per page. The page is a ruler: the home page opens on a giant 0–100 ruler reading Strength 57 and closes on the same ruler, empty ("Find your number. Then move it."). The approved artboards are the site's two pages on the design canvas ([docs/design.md](../docs/design.md)); the per-app page is drawn for Stadig Lift and both apps' pages come from one template. Designed at 1440 and fluid down to 390: below 1180 the screens go into a sideways snap scroller and the two-column chapters stack; below 860 the nav folds into a Menu (a `<details>`, no script).

## Where things live

- `src/content/site.ts` is the only place copy lives. Every page, the JSON-LD, `llms.txt` and `llms-full.txt` render from it, so the site, Google and language models all read the same facts. Edit copy there. Each app's entry carries its whole page: hero screens, the three-word interface, a day or a session, how it works, the paper "in detail" list, progress, what's free and the other app.
- `src/styles/global.css` holds the tokens (the apps' palette: `--lift` ultramarine, `--macro` leaf; `.paper` flips a section to the light theme and re-resolves the app's accent) and every layout rule. Components carry no styles of their own.
- `src/components/`: `BigRuler` (the 0–100 ruler, filled or empty), `Reading` (a giant numeral with its name and trend word), `Rule` (a section's ruler edge and label), `Figure` (a real screen in a device edge, or Watch faces), `ScoreShape` (Your shape, the six scores as a hexagon), `Free` (the "Free. All of it." section), `StoreButton`, `Header`, `Footer`.
- `src/pages/[app].astro` builds the app pages from `apps`: `/lift` and `/macro`.
- `src/layouts/Base.astro` carries the head: canonical, Open Graph, Twitter, theme colour, and the Organization and WebSite JSON-LD on every page. Pages add SoftwareApplication (free: `price` 0), FAQPage and BreadcrumbList.
- `src/pages/llms.txt.ts` and `llms-full.txt.ts` follow the llms.txt convention for LLM crawlers and answer engines. `public/robots.txt` explicitly allows them.
- `public/shots/` holds the apps' real screens, captured on the iPhone simulator (1206 × 2622) and the Watch, in dark mode: the iPhone ones resized to 624 wide (twice the largest size shown) with the status bar painted out in the screen's own ink, then WebP at quality 80, each under 60 KB. Images are cached for a year as immutable (`vercel.json`), so each capture is named with a hash of its contents (`lift-today.527cb3cf.webp`: `shasum` of the file, first 8 characters), and a recapture gets new names.
  To recapture: this checkout's simulator (`Scripts/build.sh simulator`) in dark mode with `xcrun simctl status_bar <udid> override --time 9:41`, and a 46 mm Series 11 or 12 Watch simulator (416 × 496, kept as captured). Stadig Lift launches with `-inMemoryStore -seedSampleData` plus `-startSession -sessionAt set|rest`, `-tab progress -yourShape` or `-exercise barbell-bench-press`; its Watch with `-sampleContext -sampleScreen rating|rest` (`-sampleRestElapsed 80` shows the level part way). Stadig Macro launches with `-inMemoryStore -seedSampleData -seedPlan` (plus `-seedToday`, `-tab plan` or `-tab progress -showShape`), and `SIMCTL_CHILD_TZ` set to a zone where it's lunchtime, or past 5 PM for What fits tonight; its Watch with `-seedHour 10` (and `-page logAgain`). The typed screens ("chick 200", "2 eggs, toast, coffee") need a throwaway XCUITest, since no launch argument types into the composer.
- `public/og.png` (the home page), `og-lift.png` and `og-macro.png` (one per app page, picked by slug) come from `sh scripts/og.sh` (needs `rsvg-convert`): the mark and "Stadig", a headline, a line under it and the ruler with a reading, on the ink ground. Re-run it if the mark, a name or a headline changes. The icons and `favicon.ico` were rendered from the same mark with `rsvg-convert`.

## What the site says

Everything on it is either in the docs or seen in the apps' screens; the sample scores are labelled as samples. Scores carry a trend word ("rising", "steady"…), never "+2 this month", because the apps don't keep a score's history yet ([agent-docs/decisions.md](../agent-docs/decisions.md)). Both apps are free, so there are no prices anywhere.

## The support form

`/support` (`src/pages/support.astro`) is a plain HTML form that posts to `/api/feedback`. That's `api/feedback.ts`, which Vercel deploys as a function because it sits in `api/`; Astro never sees it except to import the form's choices and limits, so the page offers exactly what the function accepts. The function checks the post came from the site's own host, drops anything that filled the hidden `homepage` field (a honeypot, the only spam defence; there's no store for rate limiting), re-checks every field, and files a GitHub issue: the one-line summary as the title, the app, kind, device, version and reply address as a list, and the person's words in a code block, so nothing they type can @mention anyone or pull in an image. Labels are the app (`Stadig Lift`, `Stadig Macro`, `website`) and the kind (`bug`, `enhancement`, `question`); if GitHub refuses them the issue is filed without. Then it redirects (303) to `/support/sent` or `/support/failed`, both kept out of search and the sitemap. Its log names what went wrong but never what the person wrote or their address. `tests/feedback.test.ts` covers all of this against a stand-in GitHub, and `Site` CI runs it.

It needs two environment variables in the Vercel project (Production and Preview):

- `FEEDBACK_REPO`: `swsvindland/stadig-feedback`, a **private** repository just for reports, not this one. The issues carry people's email addresses, and this repository is meant to go public. It has a label for each app and one for the website; GitHub's own `bug`, `enhancement` and `question` cover the kinds.
- `FEEDBACK_TOKEN`: a fine-grained personal access token for that repository only, with **Issues: Read and write** and nothing else. Give it an expiry and put the renewal in the calendar: when it lapses, every report lands on the failed page and the function logs `GitHub answered 401`.

Without them every report goes to the failed page, which can only say to try again: the form is the one way to write. The site gives no email address, because `stadig.dev` is registered through Vercel, which hosts no mail, so nothing receives at the domain (an address would need MX records for a mailbox or a forwarder first). `astro dev` and `astro preview` don't run the function; after a deploy, opening `/api/feedback` should land on `/support` (anything but a post is sent there), which shows the function is live.

## Deploying on Vercel

Import the repo, set **Root Directory** to `Site`, framework preset Astro. `vercel.json` adds `cleanUrls` (so `/faq` serves `faq.html`), immutable caching for images, security headers, and permanent redirects from the pre-rename paths (`/lift-track`, `/macro-track` and their OG images) and the retired ones (`/mind`, `/mind-track`). Set the production domain to `stadig.dev`; `astro.config.mjs` has `site` set to that, which the sitemap, canonical URLs and OG tags use.

## Still to do

- Open source: the repository is under the GPL-3.0 (`LICENSE`). Once it's public, follow the comment on `brand.free` in `src/content/site.ts` (the line under the buttons, a "Read the source" link with the licence in the Free section, and "Source" in the footer). The site doesn't claim it until then.
- If it isn't done yet: make the reports repository's token and set `FEEDBACK_REPO` and `FEEDBACK_TOKEN` in Vercel (the support form, above), then send one report through the live form to see it arrive. Both apps' App Store Support URL already points at `/support`.
