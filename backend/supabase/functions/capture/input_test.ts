// © Pexilim
import { localDay, parseCapture, sha256, TOKEN } from "./input.ts";

Deno.test("captures are checked before saving", () => {
  const ok = parseCapture({ amount: "€8,50", merchant: "  REWE   Markt ", card: "N26" });
  if (typeof ok === "string" || ok.amount !== 8.5 || ok.merchant !== "REWE Markt" || ok.card !== "N26") throw new Error(JSON.stringify(ok));
  if (typeof parseCapture({ amount: "$5" }) !== "string") throw new Error("non-euro accepted");
  if (typeof parseCapture({ amount: "-5" }) !== "string" || typeof parseCapture(null) !== "string") throw new Error("bad input accepted");
  const blank = parseCapture({ amount: 3 });
  if (typeof blank === "string" || blank.merchant !== "Apple Pay") throw new Error("no merchant");
});

Deno.test("tokens and days", () => {
  if (!TOKEN.test("blk_" + "a".repeat(43)) || TOKEN.test("blk_short") || TOKEN.test("Bearer x")) throw new Error("token shape");
  // 23:30 in Berlin on 13 Oct is 21:30 UTC: still the 13th there.
  if (localDay("Europe/Berlin", new Date("2026-10-13T21:30:00Z")) !== "2026-10-13") throw new Error("berlin day");
  if (localDay("Not/AZone", new Date("2026-10-13T21:30:00Z")) !== "2026-10-13") throw new Error("bad zone falls back");
});

Deno.test("the token hash matches the app's (SHA-256 of \"abc\", the same vector as the Swift test)", async () => {
  if (await sha256("abc") !== "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") throw new Error("hash format");
});
