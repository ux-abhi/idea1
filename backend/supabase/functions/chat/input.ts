// © Pexilim
// The trust boundary for chat requests, kept free of server code so it can be tested on its own.

export type Turn = { role: "user" | "assistant"; text: string };
export type Reminder = { id: string; title: string; due: string | null };
export type ChatRequest = { message: string; history: Turn[]; timeZone: string; reminders: Reminder[]; context: string | null };

export const MAX_MESSAGE = 2000;
export const MAX_TURNS = 20;
export const MAX_TURN_TEXT = 4000;
export const MAX_CONTEXT = 4000;

/** Returns the checked request, or a sentence saying what's wrong. */
export function parseChatRequest(body: unknown): ChatRequest | string {
  if (typeof body !== "object" || body === null) return "Send a JSON body.";
  const { message, history = [], timeZone = "UTC", reminders = [], context = null } = body as Record<string, unknown>;
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
  // Open Apple Reminders, sent by the Mac so Claude can propose completing or deleting one.
  if (!Array.isArray(reminders) || reminders.length > 50) return "reminders must be at most 50 items.";
  const checked: Reminder[] = [];
  for (const r of reminders) {
    const { id, title, due } = (r ?? {}) as Record<string, unknown>;
    if (typeof id !== "string" || id.length > 200 || typeof title !== "string" || title.length > 500 ||
        (due !== null && due !== undefined && (typeof due !== "string" || Number.isNaN(Date.parse(due))))) {
      return "Each reminder needs an id, a title and an optional ISO due date.";
    }
    checked.push({ id, title, due: typeof due === "string" ? due : null });
  }
  // What's on the owner's screen (an open note, a Space): it goes inside <blink_data>, so it's read as data, never obeyed.
  if (context !== null && (typeof context !== "string" || context.length > MAX_CONTEXT)) {
    return `context must be text of at most ${MAX_CONTEXT} characters.`;
  }
  return { message: message.trim(), history: turns, timeZone, reminders: checked, context: context?.trim() || null };
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

/** A proposed change to an existing task or reminder: the id must be one Blink showed Claude. */
export function parseChange(input: unknown, known: Map<string, string>):
  { kind: "task" | "reminder"; id: string; title: string } | null {
  const { kind, id } = (input ?? {}) as Record<string, unknown>;
  if ((kind !== "task" && kind !== "reminder") || typeof id !== "string") return null;
  const title = known.get(`${kind}:${id}`);
  return title === undefined ? null : { kind, id, title };
}

/** A proposed new due time for an existing task or reminder Blink showed Claude. */
export function parseReschedule(input: unknown, known: Map<string, string>):
  { kind: "task" | "reminder"; id: string; title: string; due: string } | null {
  const change = parseChange(input, known);
  const { due_at } = (input ?? {}) as Record<string, unknown>;
  if (!change || typeof due_at !== "string" || Number.isNaN(Date.parse(due_at))) return null;
  return { ...change, due: new Date(due_at).toISOString() };
}

/** A proposed reply-and-send for an email Blink showed the model: a known email id, an optional future send time and note. */
export function parseMailSend(input: unknown, known: Map<string, string>, now = Date.now()):
  { id: string; subject: string; sendAt: string | null; note: string } | null {
  const { email_id, send_at, note } = (input ?? {}) as Record<string, unknown>;
  if (typeof email_id !== "string") return null;
  const subject = known.get(`mail:${email_id}`);
  if (subject === undefined) return null;
  if (note !== undefined && note !== null && (typeof note !== "string" || note.length > 1000)) return null;
  let sendAt: string | null = null;
  if (send_at !== null && send_at !== undefined) {
    if (typeof send_at !== "string" || Number.isNaN(Date.parse(send_at))) return null;
    const at = Date.parse(send_at);
    if (at > now + 60_000) sendAt = new Date(at).toISOString(); // a time in the past or right now means "send now"
  }
  return { id: email_id, subject, sendAt, note: typeof note === "string" ? note.trim() : "" };
}
