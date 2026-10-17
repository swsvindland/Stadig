import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

export default defineConfig({
  site: "https://stadig.dev",
  output: "static",
  trailingSlash: "never",
  compressHTML: true,
  build: { format: "file", inlineStylesheets: "always" },
  integrations: [sitemap()],
});
