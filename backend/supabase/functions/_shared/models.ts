// © Pexilim
// Which AI writes what (ARCHITECTURE §19, §31): the owner picks a model per feature in Settings, stored in
// profile.model_prefs. Only models on this list are ever called, whatever the stored value says.

export type Provider = "claude" | "groq";
export type Feature = "chat" | "content";
export type Model = {
  id: string;
  provider: Provider;
  /** Price per million input / output tokens in USD, for the cost meter. */
  inPerM: number;
  outPerM: number;
};

// shortcut: list prices typed in by hand (Claude: Anthropic pricing page; Groq: console pricing, 0 on the free tier
// isn't assumed); refresh when a model is added, or read them from a pricing table if the list grows.
export const MODELS: Model[] = [
  { id: "claude-opus-5-5", provider: "claude", inPerM: 4, outPerM: 20 },
  { id: "claude-sonnet-5-5", provider: "claude", inPerM: 3, outPerM: 15 },
  { id: "claude-haiku-5-5", provider: "claude", inPerM: 1, outPerM: 5 },
  { id: "openai/gpt-oss-120b", provider: "groq", inPerM: 0.15, outPerM: 0.6 },
  { id: "openai/gpt-oss-20b", provider: "groq", inPerM: 0.075, outPerM: 0.3 },
  { id: "llama-3.3-70b-versatile", provider: "groq", inPerM: 0.59, outPerM: 0.79 },
  { id: "qwen/qwen3.8-27b", provider: "groq", inPerM: 0.29, outPerM: 0.59 },
  { id: "minimaxai/minimax-m2.7", provider: "groq", inPerM: 0.3, outPerM: 1.2 },
];

const FALLBACK = "claude-opus-5-5";

/** The owner's choice for a feature if it's on the list; otherwise the server's default (an env var or Opus). */
export function pickModel(prefs: unknown, feature: Feature, envDefault?: string): Model {
  const wanted = (prefs as Record<string, unknown> | null)?.[feature];
  return MODELS.find((m) => m.id === wanted) ?? MODELS.find((m) => m.id === envDefault) ?? MODELS.find((m) => m.id === FALLBACK)!;
}

export function cost(model: Model, inputTokens: number, outputTokens: number): number {
  return (inputTokens * model.inPerM + outputTokens * model.outPerM) / 1_000_000;
}

/** One call to Groq's OpenAI-compatible chat endpoint. Throws a sentence the app can show. */
export async function groq(body: Record<string, unknown>): Promise<{
  message: { content?: string | null; tool_calls?: { id: string; function: { name: string; arguments: string } }[] };
  usage: { prompt_tokens?: number; completion_tokens?: number };
}> {
  const key = Deno.env.get("GROQ_API_KEY");
  if (!key) throw new Error("Add your Groq API key to this server's Edge Function secrets first.");
  const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (response.status === 401) throw new Error("The Groq API key on this server isn't valid.");
  if (response.status === 429) throw new Error("The free Groq limit is used up for now. Try again later or switch model in Settings.");
  if (!response.ok) {
    console.error("groq", response.status, await response.text().catch(() => ""));
    throw new Error(`Groq returned an error (${response.status}).`);
  }
  const result = await response.json();
  return { message: result?.choices?.[0]?.message ?? {}, usage: result?.usage ?? {} };
}
