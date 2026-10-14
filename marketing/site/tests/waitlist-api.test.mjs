// © Pexilim
import assert from "node:assert/strict";
import { test } from "node:test";

process.env.MAILER_SECRET = "m".repeat(64);
process.env.RESEND_KEY = "re_test";
process.env.RESEND_FROM = "Blink <hello@blinkk.app>";
const { POST } = await import("../api/waitlist.mjs");

function fakeNetwork(upstream) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes("resend.com")) return new Response("{}", { status: 200 });
    return Response.json(upstream.body, { status: upstream.status });
  };
  return calls;
}
const post = (body) => POST(new Request("https://www.blinkk.app/api/waitlist", { method: "POST", body: JSON.stringify(body) }));

test("a new signup is emailed, and the browser never sees the links", async () => {
  const calls = fakeNetwork({ status: 200, body: { ok: true, mail: { to: "sam@example.com", confirm: "https://www.blinkk.app/confirm.html?t=abc", leave: "https://www.blinkk.app/leave.html?u=def" } } });
  const res = await post({ email: "sam@example.com", consent: true, website: "", source: "site", extra: "dropped" });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true });
  assert.equal(calls[0].init.headers["x-blink-mailer"], "m".repeat(64));
  assert.deepEqual(JSON.parse(calls[0].init.body), { email: "sam@example.com", consent: true, website: "", source: "site" });
  const [sent] = JSON.parse(calls[1].init.body);
  assert.equal(sent.to, "sam@example.com");
  assert.ok(sent.html.includes("confirm.html?t=abc") && sent.text.includes("leave.html?u=def"));
});

test("already listed: no email; errors pass through without detail", async () => {
  let calls = fakeNetwork({ status: 200, body: { ok: true } });
  assert.equal((await post({ email: "sam@example.com", consent: true })).status, 200);
  assert.equal(calls.length, 1);
  fakeNetwork({ status: 400, body: { error: "Please tick the box so we may email you." } });
  const bad = await post({ email: "sam@example.com" });
  assert.equal(bad.status, 400);
  assert.equal((await bad.json()).error, "Please tick the box so we may email you.");
  fakeNetwork({ status: 500, body: {} });
  assert.equal((await post({ email: "x@example.com", consent: true })).status, 502);
});
