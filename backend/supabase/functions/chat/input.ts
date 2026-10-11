// © Pexilim
// The trust boundary for chat requests, kept free of server code so it can be tested on its own.

export type Turn = { role: "user" | "assistant"; text: string };
export type ChatRequest = { message: string; history: Turn[]; timeZone: string };

export const MAX_MESSAGE = 2000;
export const MAX_TURNS = 20;
export const MAX_TURN_TEXT = 4000;

/** Returns the checked request, or a sentence saying what's wrong. */
export function parseChatRequest(body: unknown): ChatRequest | string {
  if (typeof body !== "object" || body === null) return "Send a JSON body.";
  const { message, history = [], timeZone = "UTC" } = body as Record<string, unknown>;
  if (typeof message !== "string" || message.trim().length === 0) return "message is required.";
  if (message.length > MAX_MESSAGE) return `message is longer than ${MAX_MESSAGE} characters.`;
  if (!Array.isArray(history) || history.length > MAX_TURNS) return `history must be at most ${MAX_TURNS} turns.`;
  const turns: Turn[] = [];
  for (const t of history) {
    const { role, text } = (t ?? {}) as Record<string, unknown>;
    if ((role !== "user" && role !== "assistant") || typeof text !== "string" || text.length > MAX_TURN_TEXT) {
      return "Each history turn needs a role (user or assistant) and text.";
    }
    turns.push({ role, text });
  }
  if (typeof timeZone !== "string" || !isTimeZone(timeZone)) return "timeZone must be an IANA name like Europe/Berlin.";
  return { message: message.trim(), history: turns, timeZone };
}

function isTimeZone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat("en", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/** Claude's tool input for a proposed task or reminder, checked before it becomes an Ask-First card. */
export function parseProposal(input: unknown): { title: string; due: string | null } | null {
  const { title, due_at } = (input ?? {}) as Record<string, unknown>;
  if (typeof title !== "string" || title.trim().length === 0 || title.length > 200) return null;
  if (due_at !== null && due_at !== undefined) {
    if (typeof due_at !== "string" || Number.isNaN(Date.parse(due_at))) return null;
    return { title: title.trim(), due: new Date(due_at).toISOString() };
  }
  return { title: title.trim(), due: null };
}

/** Claude Opus 5.5 list prices per million tokens, for the model_usage cost meter. */
export function costUSD(inputTokens: number, outputTokens: number): number {
  return (inputTokens * 4 + outputTokens * 20) / 1_000_000;
}
