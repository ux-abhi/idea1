// © Pexilim
import assert from "node:assert/strict";
import { test } from "node:test";

process.env.MAILER_SECRET = "m".repeat(64);
process.env.RESEND_KEY = "re_test";
process.env.RESEND_FROM = "Blink <hello@blinkk.app>";
process.env.NOTIFY_EMAIL = "owner@example.com";
process.env.MAIL_SIGNER = "Sam";
const { POST } = await import("../lib/survey.mjs");

function fakeNetwork(mail) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes("resend.com")) return new Response("{}", { status: 200 });
    return Response.json({ ok: true, mail }, { status: 200 });
  };
  return calls;
}
const send = (token) => POST(new Request("https://www.blinkk.app/api/survey", { method: "POST", body: JSON.stringify({ token }) }));
const answers = { slips: ["late-meetings"], uses: [], first_feature: "meet", pay: "month-3-5", beta: "yes", notch: true, note: "<b>hi</b>" };

test("a beta yes gets a thank-you naming who'll write, and the owner gets every answer, escaped", async () => {
  const calls = fakeNetwork({ to: "kai@example.com", leave: "https://www.blinkk.app/leave.html?u=b", answers });
  assert.equal((await send("t1")).status, 200);
  assert.equal(JSON.parse(calls[0].init.body).action, "finished");
  assert.equal(calls[0].init.headers["x-blink-mailer"], "m".repeat(64));
  const [thanks, owner] = JSON.parse(calls[1].init.body);
  assert.equal(thanks.to, "kai@example.com");
  assert.ok(thanks.text.includes("Sam will email you personally"));
  assert.equal(owner.to, "owner@example.com");
  assert.equal(owner.subject, "New beta tester: kai@example.com");
  assert.ok(owner.html.includes("&lt;b&gt;hi") && !owner.html.includes("<b>hi"));
  assert.equal(owner.headers, undefined);
});

test("no beta: only the owner hears; already sent: nobody does", async () => {
  let calls = fakeNetwork({ to: "kai@example.com", leave: "x", answers: { ...answers, beta: "maybe" } });
  await send("t1");
  assert.deepEqual(JSON.parse(calls[1].init.body).map((m) => m.to), ["owner@example.com"]);
  calls = fakeNetwork(null);
  await send("t1");
  assert.equal(calls.length, 1);
  assert.equal((await send(42)).status, 400);
});
