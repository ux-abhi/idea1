// © Pexilim
// The trust boundary for Apple Pay capture: what the owner's Shortcuts automation sends, checked before anything is saved.
import { parseMoney } from "../_shared/spend.ts";
export { localDay } from "../_shared/spend.ts";

export type Capture = { amount: number; merchant: string; card: string };

/** A capture token: "blk_" and 43 URL-safe characters (32 random bytes). */
export const TOKEN = /^blk_[A-Za-z0-9_-]{43}$/;

/** { amount: "€8.50" | 8.5, merchant: "REWE", card?: "N26 Mastercard" }; euros only for now. */
export function parseCapture(body: unknown): Capture | string {
  const { amount, merchant, card } = (body ?? {}) as Record<string, unknown>;
  const money = parseMoney(amount);
  if (!money) return "amount must be a positive amount, like 8.50";
  // shortcut: euros only (the app shows one currency); store others with their currency when a non-EUR owner appears.
  if (money.currency !== "EUR") return `Only euros for now (got ${money.currency}).`;
  const name = typeof merchant === "string" ? merchant.replace(/\s+/g, " ").trim().slice(0, 200) : "";
  return { amount: money.amount, merchant: name || "Apple Pay", card: typeof card === "string" ? card.trim().slice(0, 100) : "" };
}

/** Hex SHA-256, as the app stores it (`\\x` + hex in capture_token.token_hash). */
export async function sha256(text: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
