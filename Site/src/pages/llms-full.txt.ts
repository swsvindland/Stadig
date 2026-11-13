import type { APIRoute } from "astro";
import { brand, apps, principles, scores, together, faq } from "../content/site";

export const GET: APIRoute = () => {
  const out: string[] = [];
  const h = (s: string) => out.push("", s, "");
  out.push(
    `# ${brand.name}: ${brand.tagline}`,
    "",
    `> ${brand.description}`,
    "",
    `${brand.name} is pronounced ${brand.pronunciation} and is ${brand.meaning} Website: ${brand.domain}. Support: ${brand.domain}/support. Contact: ${brand.email}. Made by ${brand.publisher}.`,
    "",
    `Price: both apps are free, all of it. No account, no ads.`,
  );

  h("## The six scores");
  out.push(
    "Each score is 0 to 100 and moves only on something you can check. Each app shows the scores it measures; with both set up, each shows all six, labelled with the app that measures each one, drawn together as \"your shape\".",
    "",
  );
  scores.forEach((s) => out.push(`- ${s.name} (${s.apps.map((a) => (a === "lift" ? "Stadig Lift" : "Stadig Macro")).join(" and ")}): ${s.source}`));

  h("## How the apps work together");
  together.forEach((t) => out.push(`- **${t.title}** ${t.body}`));

  h("## Principles");
  principles.forEach((p, i) => out.push(`${i + 1}. **${p.title}.** ${p.body}`));

  for (const a of apps) {
    h(`# ${a.name}`);
    out.push(`URL: ${brand.domain}/${a.slug}`, `Platforms: ${a.platforms.join(", ")}`, `Price: free. ${a.free.lede}`, "", a.description, "", a.lede);
    h(`## ${a.rates.eyebrow}`);
    a.rates.items.forEach((r) => out.push(`- **${r.word}** (${r.eyebrow.toLowerCase()}): ${r.body}`));
    h(`## ${a.session.title}`);
    out.push(a.session.lede, "");
    a.session.points.forEach((p) => out.push(`- **${p.title}.** ${p.body}`));
    h(`## How ${a.name} works`);
    a.how.forEach((s, i) => out.push(`${i + 1}. **${s.title}.** ${s.body}`));
    h(`## ${a.name} features`);
    a.features.forEach((f) => out.push(`- **${f.title}.** ${f.body}`));
    h(`## Included, free`);
    out.push(a.free.items.join(", ") + ".");
    out.push("", `Keywords: ${a.keywords.join(", ")}`);
  }

  h("# FAQ");
  faq.forEach((f) => out.push(`**Q: ${f.q}**`, "", `A: ${f.a}`, ""));

  return new Response(out.join("\n"), { headers: { "Content-Type": "text/plain; charset=utf-8" } });
};
