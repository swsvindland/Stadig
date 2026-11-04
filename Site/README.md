# stadig.dev

The marketing site for Stadig (Stadig Lift, Stadig Macro and Stadig Mind). Astro, static output, zero client-side JavaScript, deployed on Vercel.

```sh
pnpm install
pnpm dev        # http://localhost:4321
pnpm build      # dist/
pnpm preview
```

## Where things live

- `src/content/site.ts` is the only place copy lives. Every page, the JSON-LD, `llms.txt` and `llms-full.txt` render from it, so the site, Google and language models all read the same facts. Edit copy there.
- `src/pages/[app].astro` builds the three app pages from `apps`: `/lift`, `/macro` and `/mind`.
- `src/layouts/Base.astro` carries the head: canonical, Open Graph, Twitter, theme colours, and the Organization and WebSite JSON-LD on every page. Pages add FAQPage, SoftwareApplication and BreadcrumbList.
- `src/pages/llms.txt.ts` and `llms-full.txt.ts` follow the llms.txt convention for LLM crawlers and answer engines. `public/robots.txt` explicitly allows them.
- `public/og.png` (the home page), `og-lift.png`, `og-macro.png` and `og-mind.png` (one per app page, picked by slug), the icons and `favicon.ico` were rendered from inline SVG with `rsvg-convert`. Re-render if the mark or a name changes. The OG images are 1200×630 on `#16160f`: the mark (64 px, `rx` 14) at 72,72 with "Stadig" in Helvetica Neue Bold 40 px (tracking −1) beside it, a 9 px accent dot (the dark-mode `--lift`, `--macro`, `--mind`, or `#faf9f6` on `og.png`), the title in Helvetica Neue Bold 76 px (tracking −3, baseline 340), the subtitle in Helvetica Neue 34 px `#c3c0b5` (baseline 430) and "stadig.dev" in 26 px `#8d8a7f` (baseline 560), all at x 72. `og.png` sets its title on two lines 82 px apart; the dot and the first line move up 41 px and the subtitle down 41 px, so the block stays centred between the mark and "stadig.dev".

## Deploying on Vercel

Import the repo, set **Root Directory** to `Site`, framework preset Astro. `vercel.json` adds `cleanUrls` (so `/faq` serves `faq.html`), immutable caching for images, security headers, and permanent redirects from the pre-rename paths (`/lift-track`, `/macro-track`, `/mind-track` and their OG images) to the new ones. Set the production domain to `stadig.dev`; `astro.config.mjs` has `site` set to that, which the sitemap, canonical URLs and OG tags use.

## Before launch

- Register `stadig.dev` (and `stadig.io` as a defensive backup). Both were free on 17 October 2026. `stadig.com` has been held by the same registrant since 2000.
- Fill in `appStoreUrl` for each app in `src/content/site.ts` once they're live; the buttons switch from "coming to the App Store" to real links on their own.
- Prices are on the site in words ($29.99 once, $2.99 a month, 21 days free): `src/content/site.ts` and the JSON-LD in `src/pages/[app].astro`. They're set in App Store Connect, and the site doesn't read them from anywhere, so change both together.
- Set up `hello@stadig.dev`.
- Replace the type-only OG images with screenshots when the apps are ready to show.
