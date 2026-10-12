// © Pexilim
// The trust boundary for text-editing requests, kept free of server code so it can be tested on its own.

export const TASKS = {
  fix: "Fix spelling, grammar and punctuation. Keep the wording, tone, language and line breaks otherwise unchanged.",
  shorter: "Make this noticeably shorter while keeping every key fact. Keep the language and tone.",
  clearer: "Rewrite this to be clearer and easier to read. Keep the meaning, language and tone.",
  summarize: "Summarise this in two to four short bullet points, in the same language.",
} as const;

export type Task = keyof typeof TASKS;
export const MAX_TEXT = 20_000;

/** Returns the checked request, or a sentence saying what's wrong. */
export function parseTextRequest(body: unknown): { task: Task; text: string } | string {
  if (typeof body !== "object" || body === null) return "Send a JSON body.";
  const { task, text } = body as Record<string, unknown>;
  if (typeof task !== "string" || !(task in TASKS)) return `task must be one of ${Object.keys(TASKS).join(", ")}.`;
  if (typeof text !== "string" || text.trim().length === 0) return "text is required.";
  if (text.length > MAX_TEXT) return `text is longer than ${MAX_TEXT} characters.`;
  return { task: task as Task, text };
}


/** The owner's text as data: "<" escaped so a "</text>" inside it can't close the block early. */
export const wrapText = (text: string) => `<text>${text.replaceAll("<", "\\u003c")}</text>`;
/** Puts back any "<" the model echoed in its escaped form, unless the owner's own note already held that text
 *  (a code note about "\\u003c" stays as written). */
export const unescapeText = (text: string, original = "") =>
  original.includes("\\u003c") ? text : text.replaceAll("\\u003c", "<");
