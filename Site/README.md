# stadig.dev

The marketing site for Stadig (Lift Track, Macro Track and Mind Track). Astro, static output, zero client-side JavaScript, deployed on Vercel.

```sh
pnpm install
pnpm dev        # http://localhost:4321
pnpm build      # dist/
pnpm preview
```

## Where things live

- `src/content/site.ts` is the only place copy lives. Every page, the JSON-LD, `llms.txt` and `llms-full.txt` render from it, so the site, Google and language models all read the same facts. Edit copy there.
- `src/pages/[app].astro` builds the three app pages from `apps`.
- `src/layouts/Base.astro` carries the head: canonical, Open Graph, Twitter, theme colours, and the Organization and WebSite JSON-LD on every page. Pages add FAQPage, SoftwareApplication and BreadcrumbList.
- `src/pages/llms.txt.ts` and `llms-full.txt.ts` follow the llms.txt convention for LLM crawlers and answer engines. `public/robots.txt` explicitly allows them.
- `public/og*.png`, the icons and `favicon.ico` were rendered from inline SVG with `rsvg-convert` (see the session that built them). Re-render if the mark changes.

## Deploying on Vercel

Import the repo, set **Root Directory** to `Site`, framework preset Astro. `vercel.json` adds `cleanUrls` (so `/faq` serves `faq.html`), immutable caching for images and security headers. Set the production domain to `stadig.dev`; `astro.config.mjs` has `site` set to that, which the sitemap, canonical URLs and OG tags use.

## Before launch

- Register `stadig.dev` (and `stadig.io` as a defensive backup). Both were free on 17 October 2026. `stadig.com` has been held by the same registrant since 2000.
- Fill in `appStoreUrl` for each app in `src/content/site.ts` once they're live; the buttons switch from "coming to the App Store" to real links on their own.
- Prices are deliberately not on the site (the StoreKit files still hold placeholders). Add them to the Pricing section when set.
- Set up `hello@stadig.dev`.
- Replace the type-only OG images with screenshots when the apps are ready to show.
