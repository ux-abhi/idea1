// © Pexilim
import { inSendingHours, isLimitError, parseBulk } from "./bulk_send.ts";

const id = (n: number) => `00000000-0000-0000-0000-${String(n).padStart(12, "0")}`;

Deno.test("a signed batch is checked before anything is sent", () => {
  const good = { campaign_id: id(1), account: "gmail", mails: [{ id: id(2), to: "ana@studio.com", subject: "Hello", body: "Hi Ana" }] };
  if (typeof parseBulk(good) === "string") throw new Error(String(parseBulk(good)));
  for (const bad of [{ ...good, account: "yahoo" }, { ...good, mails: [] },
                     { ...good, mails: [{ ...good.mails[0], to: "ana@studio.com, boss@work.com" }] },
                     { ...good, mails: [{ ...good.mails[0], body: "  " }] },
                     { ...good, mails: Array.from({ length: 101 }, () => good.mails[0]) }]) {
    if (typeof parseBulk(bad) !== "string") throw new Error(`accepted ${JSON.stringify(bad).slice(0, 120)}`);
  }
});

Deno.test("a provider asking to slow down pauses the batch; a wrong address doesn't", () => {
  for (const text of ["421 4.7.0 Try again later", "550 5.4.5 Daily user sending quota exceeded", "454 Too many login attempts"]) {
    if (!isLimitError(text)) throw new Error(text);
  }
  if (isLimitError("550 5.1.1 The email account that you tried to reach does not exist")) throw new Error("a bounce is not a limit");
});

Deno.test("mail goes out only between 8:00 and 20:00 in the owner's time zone", () => {
  const at = new Date("2026-11-21T06:30:00Z"); // 07:30 in Berlin, 06:30 UTC
  if (inSendingHours(at, "Europe/Berlin") || inSendingHours(at, "UTC")) throw new Error("sent before 8:00");
  if (!inSendingHours(new Date("2026-11-21T09:00:00Z"), "Europe/Berlin")) throw new Error("not sent at 10:00");
  if (inSendingHours(new Date("2026-11-21T19:30:00Z"), "Europe/Berlin")) throw new Error("sent at 20:30");
  if (!inSendingHours(new Date("2026-11-21T12:00:00Z"), "Not/AZone")) throw new Error("an unknown zone should fall back to UTC");
});
