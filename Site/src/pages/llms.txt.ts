import type { APIRoute } from "astro";
import { brand, apps } from "../content/site";

export const GET: APIRoute = () => {
  const lines = [
    `# ${brand.name}`,
    ``,
    `> ${brand.description}`,
    ``,
    `${brand.name} (pronounced ${brand.pronunciation}) is ${brand.meaning} Both apps are free, all of it, with no account and no ads, and open source under the ${brand.license} (${brand.source}). They follow seven principles: prescribe don't describe; real-world tests over time in the app; no XP and no streaks; offline first; private by construction; free, all of it; no third-party code. Six scores (Strength, Physique, Endurance, Agility, Vitality and Discipline), each 0 to 100, are drawn together as "your shape". Made by ${brand.publisher}.`,
    ``,
    `## Apps`,
    ``,
    ...apps.map((a) => `- [${a.name}](${brand.domain}/${a.slug}): ${a.description}`),
    ``,
    `## Company`,
    ``,
    `- [Principles](${brand.domain}/principles): The seven rules both apps follow, and what moves each score.`,
    `- [FAQ](${brand.domain}/faq): Cost, the six scores, offline use, privacy, devices, and the ideas behind the apps.`,
    `- [Support](${brand.domain}/support): Report a problem, suggest an idea or ask a question.`,
    `- [Privacy](${brand.domain}/privacy): No accounts, no analytics, no third-party SDKs.`,
    ``,
    `## Optional`,
    ``,
    `- [Full text](${brand.domain}/llms-full.txt): Every page's content in one Markdown file.`,
    ``,
  ];
  return new Response(lines.join("\n"), { headers: { "Content-Type": "text/plain; charset=utf-8" } });
};
