import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

export default defineConfig({
  site: "https://stadig.dev",
  output: "static",
  trailingSlash: "never",
  compressHTML: true,
  build: { format: "file", inlineStylesheets: "always" },
  // The support form's sent and failed pages are only reached by sending it.
  integrations: [sitemap({ filter: (page) => !page.includes("/support/") })],
});
