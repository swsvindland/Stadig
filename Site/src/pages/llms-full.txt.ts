import type { APIRoute } from "astro";
import { brand, apps, principles, stats, together, faq } from "../content/site";

export const GET: APIRoute = () => {
  const out: string[] = [];
  const h = (s: string) => out.push("", s, "");
  out.push(`# ${brand.name}: ${brand.tagline}`, "", `> ${brand.description}`, "", `${brand.name} is pronounced ${brand.pronunciation} and is ${brand.meaning} Website: ${brand.domain}. Contact: ${brand.email}. Made by ${brand.publisher}.`);

  h("## How the apps work together");
  together.forEach((t) => out.push(`- **${t.title}** ${t.body}`));

  h("## Principles");
  principles.forEach((p, i) => out.push(`${i + 1}. **${p.title}.** ${p.body}`));

  h("## Stats and what moves them");
  stats.forEach((s) => out.push(`- ${s.name}: ${s.source}.`));

  for (const a of apps) {
    h(`# ${a.name}`);
    out.push(`URL: ${brand.domain}/${a.slug}`, `Platforms: ${a.platforms.join(", ")}`, `Pricing: ${a.free}`, "", a.description, "", ...a.intro.map((p) => p + "\n"));
    h(`## How ${a.name} works`);
    a.how.forEach((s, i) => out.push(`${i + 1}. **${s.title}.** ${s.body}`));
    h(`## ${a.name} features`);
    a.features.forEach((f) => out.push(`- **${f.title}.** ${f.body}`));
    out.push("", `Keywords: ${a.keywords.join(", ")}`);
  }

  h("# FAQ");
  faq.forEach((f) => out.push(`**Q: ${f.q}**`, "", `A: ${f.a}`, ""));

  return new Response(out.join("\n"), { headers: { "Content-Type": "text/plain; charset=utf-8" } });
};
