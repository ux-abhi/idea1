// © Pexilim
// Which AI writes what (ARCHITECTURE §19, §31): the owner picks a model per feature in Settings, stored in
// profile.model_prefs. Only models on this list are ever called, whatever the stored value says.

export type Provider = "claude" | "groq" | "openrouter";
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
  // OpenRouter, the owner's small prepaid credit: only the best few, picked by hand (owner: "use it for best only").
  { id: "openai/gpt-6.1-sol", provider: "openrouter", inPerM: 2, outPerM: 10 },
  { id: "google/gemini-3.1-pro-preview", provider: "openrouter", inPerM: 2, outPerM: 12 },
  { id: "moonshotai/kimi-k3", provider: "openrouter", inPerM: 0.73, outPerM: 10 },
  { id: "deepseek/deepseek-v4-pro", provider: "openrouter", inPerM: 0.96, outPerM: 1.91 },
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

/** Claude's usage block priced the way Anthropic bills it: cache writes at 1.25x input, cache reads at 0.1x. */
export function claudeUsageCost(model: Model, usage: {
  input_tokens: number; output_tokens: number; cache_creation_input_tokens?: number | null; cache_read_input_tokens?: number | null;
}): number {
  const input = usage.input_tokens + 1.25 * (usage.cache_creation_input_tokens ?? 0) + 0.1 * (usage.cache_read_input_tokens ?? 0);
  return cost(model, input, usage.output_tokens);
}

const ENDPOINTS = {
  groq: { url: "https://api.groq.com/openai/v1/chat/completions", secret: "GROQ_API_KEY", name: "Groq" },
  openrouter: { url: "https://openrouter.ai/api/v1/chat/completions", secret: "OPENROUTER_API_KEY", name: "OpenRouter" },
};

/** Models that cost money per call (counted against the daily limit); Groq's free tier doesn't. */
export const isPaid = (modelID: string) => (MODELS.find((m) => m.id === modelID)?.provider ?? "claude") !== "groq";

/** Whether the model keeps to a JSON schema (OpenRouter's picks and GPT-OSS on Groq do); others get JSON mode. */
export const keepsSchema = (model: Model) => model.provider === "openrouter" || model.id.startsWith("openai/gpt-oss");

/** One call to an OpenAI-compatible chat endpoint (Groq or OpenRouter). Throws a sentence the app can show. */
export async function compatible(provider: "groq" | "openrouter", body: Record<string, unknown>): Promise<{
  message: { content?: string | null; tool_calls?: { id: string; function: { name: string; arguments: string } }[] };
  usage: { prompt_tokens?: number; completion_tokens?: number };
}> {
  const endpoint = ENDPOINTS[provider];
  const key = Deno.env.get(endpoint.secret);
  if (!key) throw new Error(`Add your ${endpoint.name} key (${endpoint.secret}) to this server's Edge Function secrets first.`);
  const response = await fetch(endpoint.url, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (response.status === 401) throw new Error(`The ${endpoint.name} key on this server isn't valid.`);
  if (response.status === 402) throw new Error(`Your ${endpoint.name} credit is used up. Top it up, or pick another model in Settings.`);
  if (response.status === 429) {
    throw new Error(provider === "groq" ? "The free Groq limit is used up for now. Try again later or switch model in Settings."
                                         : "OpenRouter is busy right now. Try again in a moment.");
  }
  if (response.status === 413) throw new Error(`That's too long for ${endpoint.name}. Pick Claude for this in Settings, or shorten it.`);
  if (!response.ok) {
    console.error(provider, response.status, await response.text().catch(() => ""));
    throw new Error(`${endpoint.name} returned an error (${response.status}).`);
  }
  const result = await response.json();
  return { message: result?.choices?.[0]?.message ?? {}, usage: result?.usage ?? {} };
}

/** The daily limit for paid models (§19), Claude and OpenRouter together: profile.settings.daily_cap_usd against the
 *  last 24 hours, or the server's BLINK_DAILY_CAP_USD (default $5) when the owner hasn't set one, so there is always a
 *  limit. Free Groq models never count and are never stopped. */
export function capProblem(model: Model, settings: unknown, usage: { model: string; cost_usd: number | string }[],
                           serverCap: unknown = envCap()): string | null {
  if (!isPaid(model.id)) return null;
  const positive = (value: unknown) => {
    const n = value === null || value === undefined || value === "" ? NaN : Number(value);
    return Number.isFinite(n) && n > 0 ? n : null;
  };
  const cap = positive((settings as Record<string, unknown> | null)?.daily_cap_usd) ?? positive(serverCap) ?? 5;
  const spent = usage.filter((u) => isPaid(String(u.model)) && !String(u.model).startsWith("@cf/") && !String(u.model).startsWith("apify/"))
    .reduce((sum, u) => sum + Number(u.cost_usd || 0), 0);
  return spent >= cap
    ? `Today's limit for paid models ($${cap}) is used up. Switch to a free model in Settings, or raise the limit there.`
    : null;
}

function envCap(): string | undefined {
  try { return Deno.env.get("BLINK_DAILY_CAP_USD"); } catch { return undefined; } // tests run without env access
}

/** Spend rows for the cap check: everything logged in the last 24 hours (the owner can read their own usage). */
export const lastDay = () => new Date(Date.now() - 86_400_000).toISOString();
