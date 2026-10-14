// © Pexilim
import assert from "node:assert/strict";
import { test } from "node:test";

process.env.CRON_SECRET = "c".repeat(64);
process.env.MAILER_SECRET = "m".repeat(64);
process.env.RESEND_KEY = "re_test";
process.env.RESEND_FROM = "Blink <hello@blinkk.app>";
const { GET } = await import("../api/followup.mjs");

test("only Vercel's cron may run the follow-up", async () => {
  globalThis.fetch = async () => assert.fail("must not reach the network");
  for (const authorization of [undefined, "Bearer wrong", `Bearer ${"c".repeat(63)}`]) {
    const res = await GET(new Request("https://www.blinkk.app/api/followup", { headers: authorization ? { authorization } : {} }));
    assert.equal(res.status, 401);
  }
});

test("each person due gets one email with their own survey link", async () => {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes("resend.com")) return new Response("{}", { status: 200 });
    return Response.json({ ok: true, mail: [
      { to: "sam@example.com", survey: "https://www.blinkk.app/survey.html?t=a1", leave: "https://www.blinkk.app/leave.html?u=b1" },
      { to: "kai@example.com", survey: "https://www.blinkk.app/survey.html?t=a2", leave: "https://www.blinkk.app/leave.html?u=b2" },
    ] });
  };
  const res = await GET(new Request("https://www.blinkk.app/api/followup", { headers: { authorization: `Bearer ${"c".repeat(64)}` } }));
  assert.deepEqual(await res.json(), { ok: true, sent: 2 });
  assert.equal(calls[0].init.headers["x-blink-mailer"], "m".repeat(64));
  assert.equal(calls.length, 2, "one batch call to Resend");
  const second = JSON.parse(calls[1].init.body)[1];
  assert.equal(second.to, "kai@example.com");
  assert.ok(second.html.includes("survey.html?t=a2") && second.text.includes("leave.html?u=b2"));
  assert.ok(!second.html.includes("t=a1"));
});
