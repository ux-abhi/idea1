// © Pexilim
import { assertEquals } from "jsr:@std/assert@1";
import { consentURL, emailFromIdToken, eventBody, eventId, parseExchange, parseMeet } from "./input.ts";

const now = new Date("2026-10-14T10:00:00Z");
const good = { meet_title: "Design review", start: "2026-10-15T13:00:00Z", minutes: 30, time_zone: "Europe/Berlin",
               guests: ["Sam@Example.com", "sam@example.com", "lee@uni.edu"] };

Deno.test("a meeting is checked before it goes to Google", () => {
  const meet = parseMeet(good, now);
  if (typeof meet === "string") throw new Error(meet);
  assertEquals(meet.guests, ["sam@example.com", "lee@uni.edu"]); // lower-cased, de-duplicated
  assertEquals(typeof parseMeet({ ...good, guests: ["not an email"] }, now), "string");
  assertEquals(typeof parseMeet({ ...good, guests: [] }, now), "string");
  assertEquals(typeof parseMeet({ ...good, start: "2026-10-14T09:00:00Z" }, now), "string"); // an hour ago
  assertEquals(typeof parseMeet({ ...good, minutes: 30.5 }, now), "string");
  assertEquals(typeof parseMeet({ ...good, time_zone: "Mars/Olympus" }, now), "string");
  assertEquals(typeof parseMeet({ ...good, meet_title: " " }, now), "string");
  assertEquals(typeof parseMeet(null, now), "string");
  assertEquals(typeof parseMeet({ ...good, guests: ["sam@example."] }, now), "string");
  assertEquals(typeof parseMeet({ ...good, guests: ["a@b..c"] }, now), "string");
});

Deno.test("the event asks for a Meet link with the action's id and ends after its length", () => {
  const meet = parseMeet(good, now);
  if (typeof meet === "string") throw new Error(meet);
  const body = eventBody(meet, "act-1") as { end: { dateTime: string }; conferenceData: { createRequest: { requestId: string } } };
  assertEquals(body.end.dateTime, "2026-10-15T13:30:00.000Z");
  assertEquals(body.conferenceData.createRequest.requestId, "act-1");
  assertEquals(eventId("1B2c-3d"), "1b2c3d");
});

Deno.test("a one-click answer needs a code, a real PKCE verifier and this Mac's own address", () => {
  const ok = { code: "4/abc", verifier: "a".repeat(43), redirect: "http://127.0.0.1:53123" };
  assertEquals(parseExchange(ok), ok);
  assertEquals(typeof parseExchange({ ...ok, redirect: "https://evil.example" }), "string");
  assertEquals(typeof parseExchange({ ...ok, redirect: "http://127.0.0.1:53123/../x" }), "string");
  assertEquals(typeof parseExchange({ ...ok, verifier: "short" }), "string");
  assertEquals(typeof parseExchange({ ...ok, code: "" }), "string");
  assertEquals(typeof parseExchange(null), "string");
});

Deno.test("the account email comes from the id token; anything else is refused", () => {
  const payload = btoa(JSON.stringify({ email: "me@gmail.com" })).replaceAll("=", "");
  assertEquals(emailFromIdToken(`x.${payload}.y`), "me@gmail.com");
  assertEquals(emailFromIdToken("garbage"), null);
  assertEquals(emailFromIdToken(undefined), null);
});

Deno.test("the consent page asks for a refresh token and only the calendar events scope", () => {
  const url = new URL(consentURL("id", "https://x.supabase.co/functions/v1/google/callback", "s"));
  assertEquals(url.searchParams.get("access_type"), "offline");
  assertEquals(url.searchParams.get("scope"), "openid email https://www.googleapis.com/auth/calendar.events");
});
