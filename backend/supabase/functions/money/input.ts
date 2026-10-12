// © Pexilim
// The trust boundary for money sorting: what the owner typed in, and what the model made of it, both checked here.

export const CATEGORIES = ["food", "groceries", "transport", "housing", "bills", "shopping", "health", "fun", "travel", "education", "other"] as const;
export type Category = typeof CATEGORIES[number];
export type Entry = { amount: number; note: string; category: Category; spent_on: string; account_id: string | null };

/** The request: free text (one evening's spends, or one /spent line) and the owner's local date. */
export function parseSortRequest(body: unknown): { text: string; today: string } | string {
  const { text, today } = (body ?? {}) as Record<string, unknown>;

  if (typeof text !== "string" || !text.trim()) return "Type what you spent.";
  if (text.length > 2000) return "That's a lot at once. Send at most 2000 characters.";
  if (typeof today !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(today) || Number.isNaN(Date.parse(today))) return "today must be YYYY-MM-DD.";
  return { text: text.trim(), today };
}

/** The model's entries, checked: positive amounts in cents, known categories, a day within the last month, and an account
 *  only if it is one of the owner's (by its exact name, case-insensitive); otherwise the default account, if any. */
export function parseEntries(output: unknown, today: string, accounts: { id: string; name: string; is_default: boolean }[] = []): Entry[] {
  const fallback = accounts.find((a) => a.is_default)?.id ?? null;
  const list = (output as { entries?: unknown })?.entries;
  if (!Array.isArray(list)) return [];
  return list.slice(0, 50).flatMap((e) => {
    const { amount, note, category, days_ago, account } = (e ?? {}) as Record<string, unknown>;
    const named = typeof account === "string" ? accounts.find((a) => a.name.toLowerCase() === account.trim().toLowerCase()) : undefined;
    const cents = Math.round(Number(amount) * 100);
    if (!Number.isFinite(cents) || cents <= 0 || cents >= 100_000_000) return [];
    // Today unless the note said otherwise; more than a month back is left out rather than dated today.
    const ago = days_ago === undefined || days_ago === null ? 0 : days_ago;
    if (!Number.isInteger(ago) || (ago as number) < 0 || (ago as number) > 31) return [];
    const day = new Date(`${today}T12:00:00Z`);
    day.setUTCDate(day.getUTCDate() - (ago as number));
    return [{
      amount: cents / 100,
      note: typeof note === "string" ? note.trim().slice(0, 300) : "",
      category: CATEGORIES.includes(category as Category) ? category as Category : "other",
      spent_on: day.toISOString().slice(0, 10),
      account_id: named?.id ?? fallback,
    }];
  });
}
