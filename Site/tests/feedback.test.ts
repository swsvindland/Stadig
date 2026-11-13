// The support form's function (api/feedback.ts), with GitHub replaced by a stub that records
// what it was sent. Run with `pnpm test` (Node's own runner; Node strips the types).
import { test, type TestContext } from "node:test";
import assert from "node:assert/strict";
import { handle, limits, trap } from "../api/feedback.ts";

const config = { repo: "owner/feedback", token: "test-token" };
const report = {
  app: "lift",
  kind: "problem",
  device: "iphone",
  version: "1.0 (12)",
  summary: "Rest timer   stops\nwhen the screen locks",
  details: "Started a set, locked the phone.\r\nThe timer froze at 1:12.",
  email: "someone@example.com",
};

function post(fields: Record<string, string>, headers: Record<string, string> = {}) {
  return new Request("https://stadig.dev/api/feedback", {
    method: "POST",
    headers: { host: "stadig.dev", origin: "https://stadig.dev", ...headers },
    body: new URLSearchParams(fields),
  });
}

type Sent = { url: string; init: RequestInit; payload: Record<string, unknown> };

/** A stand-in for GitHub that answers each call with the next status. */
function github(...statuses: number[]) {
  const calls: Sent[] = [];
  const send = (async (url: string, init: RequestInit) => {
    calls.push({ url, init, payload: JSON.parse(String(init.body)) });
    const status = statuses[calls.length - 1] ?? 201;
    return new Response(status === 201 ? "{}" : `{"message":"status ${status}"}`, { status });
  }) as typeof fetch;
  return { calls, send };
}

/** Keeps the function's error log out of the test output, and lets a test read it. */
const quiet = (t: TestContext) => t.mock.method(console, "error", () => {});

test("a report becomes one issue, and the person lands on the sent page", async (t) => {
  quiet(t);
  const gh = github(201);
  const response = await handle(post(report), config, gh.send);
  assert.equal(response.status, 303);
  assert.equal(response.headers.get("location"), "/support/sent");
  assert.equal(gh.calls.length, 1);

  const [call] = gh.calls;
  assert.equal(call.url, "https://api.github.com/repos/owner/feedback/issues");
  assert.equal(call.init.method, "POST");
  const headers = new Headers(call.init.headers);
  assert.equal(headers.get("authorization"), "Bearer test-token");
  assert.equal(headers.get("x-github-api-version"), "2022-11-28");
  assert.ok(headers.get("user-agent"));

  assert.equal(call.payload.title, "Rest timer stops when the screen locks");
  assert.deepEqual(call.payload.labels, ["Stadig Lift", "bug"]);
  const body = String(call.payload.body);
  for (const line of ["**App:** Stadig Lift", "**Kind:** Something's broken", "**Device:** iPhone", "`1.0 (12)`", "`someone@example.com`"]) {
    assert.ok(body.includes(line), `body has ${line}`);
  }
  assert.ok(body.includes("```text\nStarted a set, locked the phone.\nThe timer froze at 1:12.\n```"), "details fenced, CRLF made LF");
});

test("the optional fields can be left out", async (t) => {
  quiet(t);
  const gh = github(201);
  const response = await handle(post({ ...report, device: "", version: "", email: "" }), config, gh.send);
  assert.equal(response.headers.get("location"), "/support/sent");
  const body = String(gh.calls[0].payload.body);
  assert.ok(body.includes("**Device:** not given"));
  assert.ok(body.includes("**Version:** not given"));
  assert.ok(body.includes("**Reply to:** no address left"));
});

test("what someone types can't mention people or break out of its code block", async (t) => {
  quiet(t);
  const gh = github(201);
  const details = "Pinging @octocat and #1.\n```\n![x](https://example.com/x.png)\n```";
  await handle(post({ ...report, details }), config, gh.send);
  const body = String(gh.calls[0].payload.body);
  assert.ok(body.includes("````text\n" + details + "\n````"), "fenced with a longer run than any inside");
});

test("a filled-in trap is told it worked and files nothing", async (t) => {
  quiet(t);
  const gh = github();
  const response = await handle(post({ ...report, [trap]: "https://spam.example" }), config, gh.send);
  assert.equal(response.headers.get("location"), "/support/sent");
  assert.equal(gh.calls.length, 0);
});

test("anything the form wouldn't send is refused without reaching GitHub", async (t) => {
  const log = quiet(t);
  const bad: Record<string, string>[] = [
    { ...report, app: "mind" },
    { ...report, kind: "" },
    { ...report, device: "android" },
    { ...report, version: "1.0; rm -rf" },
    { ...report, version: "1".repeat(limits.version + 1) },
    { ...report, summary: "   " },
    { ...report, summary: "x".repeat(limits.summary + 1) },
    { ...report, details: "" },
    { ...report, details: "x".repeat(limits.details + 1) },
    { ...report, email: "not an address" },
  ];
  for (const fields of bad) {
    const gh = github();
    const response = await handle(post(fields), config, gh.send);
    assert.equal(response.headers.get("location"), "/support/failed", JSON.stringify(fields));
    assert.equal(gh.calls.length, 0);
  }
  for (const call of log.mock.calls) {
    const line = String(call.arguments[0]);
    assert.ok(!line.includes("someone@example.com") && !line.includes("Started a set"), "the log never carries the report");
  }
});

test("details at the limit pass, counting a CRLF as one character", async (t) => {
  quiet(t);
  const gh = github(201);
  const details = "x".repeat(limits.details - 2) + "\r\n" + "y";
  const response = await handle(post({ ...report, details }), config, gh.send);
  assert.equal(response.headers.get("location"), "/support/sent");
});

test("a post from another site is refused; one from the page's own host goes through", async (t) => {
  quiet(t);
  for (const origin of ["https://evil.example", "null"]) {
    const elsewhere = github();
    const refused = await handle(post(report, { origin }), config, elsewhere.send);
    assert.equal(refused.headers.get("location"), "/support/failed", origin);
    assert.equal(elsewhere.calls.length, 0);
  }

  const preview = github(201);
  const ok = await handle(
    post(report, { host: "stadig-git-main.vercel.app", origin: "https://stadig-git-main.vercel.app" }),
    config,
    preview.send,
  );
  assert.equal(ok.headers.get("location"), "/support/sent");
});

test("labels GitHub won't apply don't lose the report", async (t) => {
  quiet(t);
  const gh = github(422, 201);
  const response = await handle(post(report), config, gh.send);
  assert.equal(response.headers.get("location"), "/support/sent");
  assert.equal(gh.calls.length, 2);
  assert.equal(gh.calls[1].payload.labels, undefined);
  assert.equal(gh.calls[1].payload.title, gh.calls[0].payload.title);
});

test("GitHub failing, or unreachable, sends the person to the failed page", async (t) => {
  const log = quiet(t);
  const down = github(503);
  assert.equal((await handle(post(report), config, down.send)).headers.get("location"), "/support/failed");

  const unreachable = (async () => {
    throw new TypeError("fetch failed");
  }) as typeof fetch;
  assert.equal((await handle(post(report), config, unreachable)).headers.get("location"), "/support/failed");
  assert.ok(log.mock.calls.some((c) => String(c.arguments[0]).includes("503")));
});

test("without its configuration nothing is filed", async (t) => {
  quiet(t);
  for (const broken of [{}, { repo: "owner/feedback" }, { token: "t" }, { repo: "../../user", token: "t" }]) {
    const gh = github();
    const response = await handle(post(report), broken, gh.send);
    assert.equal(response.headers.get("location"), "/support/failed");
    assert.equal(gh.calls.length, 0);
  }
});

test("anything but a post goes to the form", async () => {
  const response = await handle(new Request("https://stadig.dev/api/feedback"), config, github().send);
  assert.equal(response.status, 303);
  assert.equal(response.headers.get("location"), "/support");
});
