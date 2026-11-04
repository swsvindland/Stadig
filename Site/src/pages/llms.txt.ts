import type { APIRoute } from "astro";
import { brand, apps } from "../content/site";

export const GET: APIRoute = () => {
  const lines = [
    `# ${brand.name}`,
    ``,
    `> ${brand.description}`,
    ``,
    `${brand.name} (pronounced ${brand.pronunciation}) is ${brand.meaning} The apps follow seven principles: prescribe don't describe; real-world tests over in-app activity; no XP, streaks or levels; offline first; private by construction; free for 21 days, then pay once or by the month; no third-party code. Made by ${brand.publisher}.`,
    ``,
    `## Apps`,
    ``,
    ...apps.map((a) => `- [${a.name}](${brand.domain}/${a.slug}): ${a.description}`),
    ``,
    `## Company`,
    ``,
    `- [Principles](${brand.domain}/principles): The seven rules every app follows, and what moves each stat.`,
    `- [FAQ](${brand.domain}/faq): Pricing, offline use, privacy, devices, and the ideas behind the apps.`,
    `- [Privacy](${brand.domain}/privacy): No accounts, no analytics, no third-party SDKs.`,
    ``,
    `## Optional`,
    ``,
    `- [Full text](${brand.domain}/llms-full.txt): Every page's content in one Markdown file.`,
    ``,
  ];
  return new Response(lines.join("\n"), { headers: { "Content-Type": "text/plain; charset=utf-8" } });
};
