// © Pexilim
// Spends that arrive on their own (Apple Pay through the owner's Shortcuts automation, receipts in mail): reading the
// amount the same strict way the app does, and never counting one payment twice.

export const CATEGORIES = ["food", "groceries", "transport", "housing", "bills", "shopping", "health", "fun", "travel", "education", "other"] as const;
export type Category = typeof CATEGORIES[number];

/** "€8.50", "8,50 €", "1.234,56 EUR", "12.99" → { amount: 8.5, currency: "EUR" }. With a comma, dots group thousands;
 *  without one, a dot is the decimal point; "1.250" is ambiguous and refused. Null for anything that isn't a positive
 *  amount under a million. Currency: an explicit code or sign, else EUR. */
export function parseMoney(text: unknown): { amount: number; currency: string } | null {
  if (typeof text === "number") {
    const amount = Math.round(text * 100) / 100; // checked after rounding: 0.001 is not a spend
    return amount > 0 && amount < 1_000_000 ? { amount, currency: "EUR" } : null;
  }
  // A minus is a refund or a credit, never a spend.
  if (typeof text !== "string" || text.length > 60 || /^\s*[-−]|[-−]\s*$/.test(text)) return null;
  const signs: Record<string, string> = { "€": "EUR", "$": "USD", "£": "GBP", "₹": "INR", "¥": "JPY", "CHF": "CHF" };
  const code = text.toUpperCase().match(/\b[A-Z]{3}\b/)?.[0] ?? Object.entries(signs).find(([sign]) => text.includes(sign))?.[1] ?? "EUR";
  const raw = text.replace(/[^\d.,]/g, "");
  // An iPhone in English writes "1,234.56" (the last separator a dot with two digits): commas group thousands there.
  // Otherwise a comma is the decimal point and dots group thousands ("1.234,56").
  const english = /,\d{3}\.\d{2}$/.test(raw);
  const plain = english ? raw.replaceAll(",", "") : raw.includes(",") ? raw.replaceAll(".", "").replace(",", ".") : raw;
  const [, cents = ""] = plain.split(".");
  if (!plain || plain.split(".").length > 2 || cents.length > 2) return null;
  const amount = Math.round(Number(plain) * 100) / 100;
  return Number.isFinite(amount) && amount > 0 && amount < 1_000_000 ? { amount, currency: code } : null;
}

/** Which of the owner's accounts a card name points at ("N26 Mastercard" → the account called "N26"), else the default. */
export function accountFor(card: unknown, accounts: { id: string; name: string; is_default: boolean }[]): string | null {
  const label = typeof card === "string" ? card.toLowerCase() : "";
  const named = label ? accounts.find((a) => label.includes(a.name.toLowerCase())) : undefined;
  return named?.id ?? accounts.find((a) => a.is_default)?.id ?? null;
}

/** Common merchants, so most taps need no AI call at all; the rest are sorted by a free model or left as "other". */
export function guessCategory(merchant: string): Category | null {
  const m = merchant.toLowerCase();
  const rules: [RegExp, Category][] = [
    [/\b(rewe|lidl|aldi|edeka|netto|penny|kaufland|denn|dm-?drogerie|rossmann|spar|tesco|carrefour|whole foods)\b/, "groceries"],
    [/\b(db|deutsche bahn|bvg|mvg|hvv|vrs|uber|bolt|lime|tier|flixbus|shell|aral|esso|total|transport)\b/, "transport"],
    [/\b(mcdonald|burger king|starbucks|subway|kfc|domino|lieferando|wolt|deliveroo|caf[eé]|restaurant|bäckerei|baeckerei|pizza)\b/, "food"],
    [/\b(apotheke|pharmacy|doctor|arzt)\b/, "health"],
    [/\b(amazon|zalando|ikea|h&m|primark|media ?markt|saturn|apple store)\b/, "shopping"],
    [/\b(netflix|spotify|cinema|kino|steam|playstation)\b/, "fun"],
  ];
  return rules.find(([pattern]) => pattern.test(m))?.[1] ?? null;
}

type Db = { from: (table: string) => any };

/** A payment already recorded: the same amount within two days either side, from any source (an Apple Pay tap and the
 *  shop's receipt mail are the same spend). */
export async function alreadyRecorded(db: Db, owner: string, amount: number, day: string): Promise<boolean> {
  const at = new Date(`${day}T12:00:00Z`);
  const from = new Date(at.getTime() - 2 * 86_400_000).toISOString().slice(0, 10);
  const to = new Date(at.getTime() + 2 * 86_400_000).toISOString().slice(0, 10);
  const { data, error } = await db.from("transaction").select("id").eq("owner_id", owner).eq("amount", amount)
    .gte("spent_on", from).lte("spent_on", to).limit(1);
  if (error) throw error;
  return (data ?? []).length > 0;
}

/** The owner's local date (spends are filed by day, and a 23:30 tap belongs to that evening, not tomorrow in UTC). */
export function localDay(timeZone: string | null | undefined, now = new Date()): string {
  try {
    return new Intl.DateTimeFormat("en-CA", { timeZone: timeZone || "UTC", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
  } catch {
    return now.toISOString().slice(0, 10);
  }
}
