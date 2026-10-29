// Run: node --test marketing/site/tests/waitlist.test.js
import { test } from "node:test";
import assert from "node:assert/strict";
import { waitlistResult, checkInput } from "../public/js/waitlist.js";

test("only 200 with ok:true counts as joined", () => {
  assert.deepEqual(waitlistResult(200, { ok: true }), { ok: true });
  assert.equal(waitlistResult(200, {}).ok, false);
  assert.equal(waitlistResult(200, null).ok, false);
  assert.equal(waitlistResult(201, { ok: true }).ok, false);
});

test("400 and 429 show the server's message, or a fallback", () => {
  assert.equal(waitlistResult(400, { error: "That email looks wrong." }).text, "That email looks wrong.");
  assert.match(waitlistResult(400, null).text, /email address/);
  assert.match(waitlistResult(429, {}).text, /Too many tries/);
  assert.match(waitlistResult(500, { error: "boom" }).text, /Couldn't reach/);
  assert.match(waitlistResult(0, null).text, /Couldn't reach/);
});

test("needs a plausible email and consent before sending", () => {
  assert.equal(checkInput("", true).field, "email");
  assert.equal(checkInput("not-an-email", true).field, "email");
  assert.equal(checkInput("a@b.co", false).field, "consent");
  assert.equal(checkInput("a@b.co", true), null);
});
