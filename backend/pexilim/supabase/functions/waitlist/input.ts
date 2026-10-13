// © Pexilim
// The trust boundary for the waitlist form: only a plain email, with consent, from a person (not the honeypot).

export type Signup = { email: string; source: string };

/** { email, consent: true, website: "" (honeypot), source? } → a signup; "bot" when the honeypot is filled; else why not. */
export function parseSignup(body: unknown): Signup | "bot" | string {
  const { email, consent, website, source } = (body ?? {}) as Record<string, unknown>;
  if (typeof website === "string" && website.trim() !== "") return "bot";
  if (consent !== true) return "Please tick the box so we may email you.";
  const address = typeof email === "string" ? email.trim().toLowerCase() : "";
  if (address.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(address)) return "That doesn't look like an email address.";
  const from = typeof source === "string" && /^[a-z0-9-]{1,40}$/.test(source) ? source : "site";
  return { email: address, source: from };
}

/** Only our site (and a local preview) may call this from a browser. */
export const ORIGINS = ["https://blink.pexilim.com", "http://localhost:8765"];
export function corsFor(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin && ORIGINS.includes(origin) ? origin : ORIGINS[0],
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Vary": "Origin",
  };
}
