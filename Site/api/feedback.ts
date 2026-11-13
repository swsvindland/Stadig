// The support form's one piece of server. The form on /support posts here as a plain HTML form,
// this files it as an issue in a private GitHub repository, and the person lands on a page saying
// which happened, so the site itself stays static and script-free. Vercel deploys every file in
// `api/` as a function; Site/README.md has the two environment variables it needs:
//
// FEEDBACK_REPO   "owner/name" of the private repository the issues go to
// FEEDBACK_TOKEN  a fine-grained token with Issues: read and write on that repository only

export type Choice = { value: string; label: string; tag?: string };

/** What the form offers. The page renders these and the function accepts nothing else. */
export const choices = {
  app: [
    { value: "lift", label: "Stadig Lift", tag: "Stadig Lift" },
    { value: "macro", label: "Stadig Macro", tag: "Stadig Macro" },
    { value: "site", label: "This website", tag: "website" },
  ],
  kind: [
    { value: "problem", label: "Something's broken", tag: "bug" },
    { value: "idea", label: "An idea", tag: "enhancement" },
    { value: "question", label: "A question", tag: "question" },
  ],
  device: [
    { value: "iphone", label: "iPhone" },
    { value: "ipad", label: "iPad" },
    { value: "mac", label: "Mac" },
    { value: "vision", label: "Apple Vision Pro" },
    { value: "watch", label: "Apple Watch" },
  ],
} satisfies Record<string, Choice[]>;

/** The form's maxlengths, checked again here since anything can post. */
export const limits = { summary: 120, details: 5000, email: 254, version: 40 };

/** The hidden field people never see and form-filling bots fill in. */
export const trap = "homepage";

export const pages = { form: "/support", sent: "/support/sent", failed: "/support/failed" };

export type Report = {
  app: Choice;
  kind: Choice;
  device?: Choice;
  version: string;
  summary: string;
  details: string;
  email: string;
};

export type Issue = { title: string; body: string; labels: string[] };

export type Config = { repo?: string; token?: string };

const field = (form: FormData, name: string) => {
  const value = form.get(name);
  return typeof value === "string" ? value.trim() : "";
};
const pick = (list: Choice[], value: string) => list.find((c) => c.value === value);

/** The report in a form, or why it was refused (for the log, never shown). */
export function readReport(form: FormData): Report | string {
  const app = pick(choices.app, field(form, "app"));
  const kind = pick(choices.kind, field(form, "kind"));
  if (!app || !kind) return "no app or kind";
  const deviceValue = field(form, "device");
  const device = deviceValue ? pick(choices.device, deviceValue) : undefined;
  if (deviceValue && !device) return "unknown device";

  const version = field(form, "version");
  if (version.length > limits.version || !/^[\w .()-]*$/.test(version)) return "bad version";
  const summary = field(form, "summary").replace(/\s+/g, " ");
  if (!summary || summary.length > limits.summary) return "no summary, or too long";
  // Browsers count a newline as one character for maxlength but send it as CRLF.
  const details = field(form, "details").replace(/\r\n?/g, "\n");
  if (!details || details.length > limits.details) return "no details, or too long";
  const email = field(form, "email");
  if (email && (email.length > limits.email || !/^[^\s@<>()`]+@[^\s@<>()`]+\.[^\s@<>()`]+$/.test(email))) return "bad email";

  return { app, kind, device, version, summary, details, email };
}

/** The issue for a report. The person's words go in a code block, so nothing they type can
 *  mention someone, link an issue or load an image in the tracker. */
export function issueFor(report: Report): Issue {
  const longestTicks = Math.max(0, ...(report.details.match(/`+/g) ?? []).map((run) => run.length));
  const fence = "`".repeat(Math.max(3, longestTicks + 1));
  const facts = [
    `- **App:** ${report.app.label}`,
    `- **Kind:** ${report.kind.label}`,
    `- **Device:** ${report.device?.label ?? "not given"}`,
    `- **Version:** ${report.version ? `\`${report.version}\`` : "not given"}`,
    `- **Reply to:** ${report.email ? `\`${report.email}\`` : "no address left"}`,
  ];
  return {
    title: report.summary,
    body: [...facts, "", `${fence}text`, report.details, fence, "", "From the support form on the site."].join("\n"),
    labels: [report.app.tag, report.kind.tag].filter((tag): tag is string => Boolean(tag)),
  };
}

/** The host of an Origin header; "null" and other junk have none. */
function hostOf(origin: string): string | undefined {
  try {
    return new URL(origin).host;
  } catch {
    return undefined;
  }
}

const redirect = (path: string) => new Response(null, { status: 303, headers: { Location: path, "Cache-Control": "no-store" } });

/** Files the issue; false if GitHub didn't take it. */
async function file(issue: Issue, config: Required<Config>, send: typeof fetch): Promise<boolean> {
  const post = (payload: object) =>
    send(`https://api.github.com/repos/${config.repo}/issues`, {
      method: "POST",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${config.token}`,
        "Content-Type": "application/json",
        "User-Agent": "stadig-site-feedback",
        "X-GitHub-Api-Version": "2022-11-28",
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(8000),
    });
  try {
    let response = await post(issue);
    // A label GitHub won't apply mustn't lose the report: file it bare.
    if (response.status === 422 && issue.labels.length > 0) {
      console.error(`feedback: GitHub refused the labels (${(await response.text()).slice(0, 300)}); filing without them`);
      response = await post({ title: issue.title, body: issue.body });
    }
    if (response.status === 201) return true;
    console.error(`feedback: GitHub answered ${response.status}: ${(await response.text()).slice(0, 300)}`);
  } catch (error) {
    console.error(`feedback: couldn't reach GitHub: ${error instanceof Error ? error.message : String(error)}`);
  }
  return false;
}

/** The whole exchange, with GitHub's fetch passed in so tests never reach it. The log names
 *  what went wrong but never carries what the person wrote or their address. */
export async function handle(request: Request, config: Config, send: typeof fetch = fetch): Promise<Response> {
  if (request.method !== "POST") return redirect(pages.form);

  // Only our own pages may post here, or any site could file issues through it.
  const origin = request.headers.get("origin");
  const host = request.headers.get("x-forwarded-host") ?? request.headers.get("host") ?? new URL(request.url).host;
  if (origin !== null && hostOf(origin) !== host) {
    console.error(`feedback: refused a post from ${origin}`);
    return redirect(pages.failed);
  }
  if (Number(request.headers.get("content-length") ?? 0) > 64_000) {
    console.error("feedback: refused an oversized post");
    return redirect(pages.failed);
  }

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    console.error("feedback: couldn't read the form");
    return redirect(pages.failed);
  }
  // A bot that filled the trap is told it worked, so it has nothing to learn from.
  if (field(form, trap)) return redirect(pages.sent);

  const report = readReport(form);
  if (typeof report === "string") {
    console.error(`feedback: refused a report: ${report}`);
    return redirect(pages.failed);
  }
  const { repo, token } = config;
  if (!repo || !/^[\w.-]+\/[\w.-]+$/.test(repo) || !token) {
    console.error("feedback: FEEDBACK_REPO or FEEDBACK_TOKEN isn't set");
    return redirect(pages.failed);
  }
  return redirect((await file(issueFor(report), { repo, token }, send)) ? pages.sent : pages.failed);
}

// Node's process.env, without taking on @types/node for one property.
const env = (globalThis as unknown as { process: { env: Record<string, string | undefined> } }).process.env;

export default {
  fetch(request: Request): Promise<Response> {
    return handle(request, { repo: env.FEEDBACK_REPO, token: env.FEEDBACK_TOKEN });
  },
};
