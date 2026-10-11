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

/** gpt-oss-20b on Groq, per million tokens, for the model_usage cost meter. */
export function groqCostUSD(inputTokens: number, outputTokens: number): number {
  return (inputTokens * 0.075 + outputTokens * 0.3) / 1_000_000;
}
