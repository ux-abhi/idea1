// © Pexilim
import { accountFor, guessCategory, parseMoney } from "./spend.ts";

Deno.test("amounts read the strict way, with their currency", () => {
  const cases: [unknown, { amount: number; currency: string } | null][] = [
    ["€8.50", { amount: 8.5, currency: "EUR" }], ["8,50 €", { amount: 8.5, currency: "EUR" }],
    ["1.234,56 EUR", { amount: 1234.56, currency: "EUR" }], ["12.99", { amount: 12.99, currency: "EUR" }],
    ["$5.00", { amount: 5, currency: "USD" }], ["€1,234.56", { amount: 1234.56, currency: "EUR" }], [0.001, null], ["1.250", null], ["-3", null], ["−4,00 €", null], ["0", null],
    ["", null], ["abc", null], [12.5, { amount: 12.5, currency: "EUR" }], [2_000_000, null],
  ];
  for (const [input, want] of cases) {
    if (JSON.stringify(parseMoney(input)) !== JSON.stringify(want)) throw new Error(`${input}: ${JSON.stringify(parseMoney(input))}`);
  }
});

Deno.test("cards point at accounts, else the default", () => {
  const accounts = [{ id: "a", name: "N26", is_default: false }, { id: "b", name: "Sparkasse", is_default: true }];
  if (accountFor("N26 Mastercard", accounts) !== "a" || accountFor("Visa", accounts) !== "b" || accountFor(undefined, []) !== null) {
    throw new Error("account matching");
  }
});

Deno.test("common merchants need no AI", () => {
  if (guessCategory("REWE Markt GmbH") !== "groceries" || guessCategory("BVG Ticket") !== "transport" || guessCategory("Mystery Shop") !== null) {
    throw new Error("categories");
  }
});
