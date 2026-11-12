# stadig.dev

The marketing site for Stadig (Stadig Lift and Stadig Macro). Astro, static output, zero client-side JavaScript, deployed on Vercel.

```sh
pnpm install
pnpm dev        # http://localhost:4321
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
- `public/shots/` holds the apps' real screens, captured on the iPhone simulator (1206 × 2622) and the Watch, in dark mode: the iPhone ones resized to 624 wide (twice the largest size shown) with the status bar painted out in the screen's own ink, then WebP at quality 80, each under 60 KB. Images are cached for a year as immutable (`vercel.json`), so a new capture gets a new file name.
- `public/og.png` (the home page), `og-lift.png` and `og-macro.png` (one per app page, picked by slug) come from `sh scripts/og.sh` (needs `rsvg-convert`): the mark and "Stadig", a headline, a line under it and the ruler with a reading, on the ink ground. Re-run it if the mark, a name or a headline changes. The icons and `favicon.ico` were rendered from the same mark with `rsvg-convert`.

## What the site says

Everything on it is either in the docs or seen in the apps' screens; the sample scores are labelled as samples. Scores carry a trend word ("rising", "steady"…), never "+2 this month", because the apps don't keep a score's history yet ([docs/decisions.md](../docs/decisions.md)). Both apps are free, so there are no prices anywhere.

## Deploying on Vercel

Import the repo, set **Root Directory** to `Site`, framework preset Astro. `vercel.json` adds `cleanUrls` (so `/faq` serves `faq.html`), immutable caching for images, security headers, and permanent redirects from the pre-rename paths (`/lift-track`, `/macro-track` and their OG images) and the retired ones (`/mind`, `/mind-track`). Set the production domain to `stadig.dev`; `astro.config.mjs` has `site` set to that, which the sitemap, canonical URLs and OG tags use.

## Before launch

- Register `stadig.dev` (and `stadig.io` as a defensive backup). Both were free on 17 October 2026. `stadig.com` has been held by the same registrant since 2000.
- Fill in `appStoreUrl` for each app in `src/content/site.ts` once they're live. Until then each App Store button names the app and says "Coming to the App Store" (a link to the app's page from elsewhere, plain text on the app's own page); with a URL they become "Stadig Lift on the App Store" links on their own.
- Open source: once the repository is public and licensed, follow the comment on `brand.free` in `src/content/site.ts` (the line under the buttons, a "Read the source" link with the licence in the Free section, and "Source" in the footer). The site doesn't claim it until then.
- Set up `hello@stadig.dev`.
