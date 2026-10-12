// © Pexilim
import { parseEntries, parseSortRequest } from "./input.ts";

Deno.test("sorted entries are checked: amounts in cents, known categories, days in the last month", () => {
  const out = parseEntries({ entries: [
    { amount: 8.499, note: " Lunch ", category: "food", days_ago: 0 },
    { amount: 23.4, note: "Rewe", category: "groceries", days_ago: 1 },
    { amount: "3", note: "Bus", category: "crypto", days_ago: 0 },
    { amount: -5, note: "refund", category: "other", days_ago: 0 },
    { amount: 5, note: "old", category: "fun", days_ago: 400 },
  ] }, "2026-10-12");
  const want = [
    { amount: 8.5, note: "Lunch", category: "food", spent_on: "2026-10-12", account_id: null },
    { amount: 23.4, note: "Rewe", category: "groceries", spent_on: "2026-10-11", account_id: null },
    { amount: 3, note: "Bus", category: "other", spent_on: "2026-10-12", account_id: null },
  ];
  if (JSON.stringify(out) !== JSON.stringify(want)) throw new Error(JSON.stringify(out));
  if (parseEntries({ entries: "nope" }, "2026-10-12").length !== 0) throw new Error("bad shape accepted");
});

Deno.test("the request needs text and a local date", () => {
  if (typeof parseSortRequest({ text: "lunch 8.50", today: "2026-10-12" }) === "string") throw new Error("valid request refused");
  if (typeof parseSortRequest({ text: " ", today: "2026-10-12" }) !== "string") throw new Error("empty text accepted");
  if (typeof parseSortRequest({ text: "x", today: "12.10.2026" }) !== "string") throw new Error("bad date accepted");
});

Deno.test("a spend comes off the account the note names, else the default; never an unknown one", () => {
  const accounts = [{ id: "a1", name: "Sparkasse", is_default: true }, { id: "a2", name: "N26", is_default: false }];
  const out = parseEntries({ entries: [
    { amount: 23.4, note: "Rewe", category: "groceries", days_ago: 0, account: "n26" },
    { amount: 3, note: "Bus", category: "transport", days_ago: 0, account: "" },
    { amount: 5, note: "Kiosk", category: "food", days_ago: 0, account: "Someone else's bank" },
  ] }, "2026-10-12", accounts);
  if (out.map((e) => e.account_id).join() !== "a2,a1,a1") throw new Error(JSON.stringify(out));
});
