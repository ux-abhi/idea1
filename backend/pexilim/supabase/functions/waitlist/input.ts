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
export const ORIGINS = ["https://www.blinkk.app", "https://blinkk.app", "http://localhost:8765"];
export function corsFor(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin && ORIGINS.includes(origin) ? origin : ORIGINS[0],
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Vary": "Origin",
  };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** { action: "confirm" | "leave" | "finished", token: uuid } from the site's confirm and leave pages, or its survey
 *  mailer ("finished"); null for anything else. */
export function parseAction(body: unknown): { kind: "confirm" | "leave" | "finished"; token: string } | null {
  const { action, token } = (body ?? {}) as Record<string, unknown>;
  if ((action !== "confirm" && action !== "leave" && action !== "finished") || typeof token !== "string" || !UUID.test(token.toLowerCase())) return null;
  return { kind: action, token: token.toLowerCase() };
}

/** The survey's choices: anything else is dropped, so nothing but these words is ever stored. */
export const CHOICES = {
  slips: ["missed-emails", "late-meetings", "forgotten-tasks", "lost-copies", "overspending", "not-posting"],
  uses: ["apple", "notion", "todoist", "ai-chat", "sticky-notes", "nothing"],
  first: ["ask", "mail", "clipboard", "meet", "money", "habits", "posts"],
  pay: ["free-only", "once-10-20", "once-20-40", "month-3-5", "month-5-10", "more"],
} as const;

export type Answers = {
  slips: string[]; uses: string[]; first_feature: string | null; pay: string | null;
  beta: "yes" | "maybe" | null; notch: boolean | null; note: string | null;
};

/** { action: "answer", token: uuid (from the confirm link), answers } from survey.html; null for anything else. */
export function parseAnswer(body: unknown): { token: string; answers: Answers } | null {
  const { action, token, answers } = (body ?? {}) as Record<string, unknown>;
  if (action !== "answer" || typeof token !== "string" || !UUID.test(token.toLowerCase())) return null;
  const a = (answers ?? {}) as Record<string, unknown>;
  const many = (value: unknown, allowed: readonly string[]) =>
    Array.isArray(value) ? [...new Set(value.filter((v): v is string => typeof v === "string" && allowed.includes(v)))] : [];
  const one = (value: unknown, allowed: readonly string[]) => typeof value === "string" && allowed.includes(value) ? value : null;
  const note = typeof a.note === "string" ? a.note.trim().slice(0, 1000) : "";
  return {
    token: token.toLowerCase(),
    answers: {
      slips: many(a.slips, CHOICES.slips), uses: many(a.uses, CHOICES.uses),
      first_feature: one(a.first, CHOICES.first), pay: one(a.pay, CHOICES.pay),
      beta: a.beta === "yes" || a.beta === "maybe" ? a.beta : null,
      notch: typeof a.notch === "boolean" ? a.notch : null,
      note: note || null,
    },
  };
}

/** The site's mailer proves itself with a shared secret; compared in constant time, and never true when unset. */
export function sameSecret(given: string | null, expected: string | undefined): boolean {
  if (!given || !expected || expected.length < 32 || given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}
