// © Pexilim
// Which AI writes what (ARCHITECTURE §19, §31): the owner picks a model per feature in Settings, stored in
// profile.model_prefs. Only models on this list are ever called, whatever the stored value says.
import { secret } from "./secrets.ts";

export type Provider = "claude" | "groq" | "openrouter" | "custom";
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
  // The owner's own AI (Settings › Connections › Advanced): any OpenAI-compatible service, its model named in
  // CUSTOM_AI_MODEL. Its price isn't known here, so it's counted at 0 (its own account has the real bill).
  { id: "custom", provider: "custom", inPerM: 0, outPerM: 0 },
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

/** "https://api.mistral.ai/v1" (or the full …/chat/completions) → the chat endpoint; null unless it's https. */
export function customEndpoint(base: string | undefined): string | null {
  const trimmed = (base ?? "").trim().replace(/\/+$/, "");
  try {
    if (new URL(trimmed).protocol !== "https:") return null;
  } catch {
    return null;
  }
  return trimmed.endsWith("/chat/completions") ? trimmed : `${trimmed}/chat/completions`;
}

type Endpoint = { url: string; key: string; name: string; model?: string };

/** Where an OpenAI-compatible call goes, with its key (and, for the owner's own AI, its model name). */
async function endpointFor(provider: Exclude<Provider, "claude">): Promise<Endpoint> {
  if (provider === "custom") {
    const name = (await secret("CUSTOM_AI_NAME"))?.trim() || "Your own AI";
    const url = customEndpoint(await secret("CUSTOM_AI_URL"));
    const key = await secret("CUSTOM_AI_KEY"), model = (await secret("CUSTOM_AI_MODEL"))?.trim();
    if (!url || !key || !model) throw new Error("Finish adding your own AI in Blink › Settings › Connections › Advanced (address, model and key).");
    return { url, key, name, model };
  }
  const endpoint = ENDPOINTS[provider];
  const key = await secret(endpoint.secret);
  if (!key) throw new Error(`Add your ${endpoint.name} key in Blink › Settings › Connections first.`);
  return { url: endpoint.url, key, name: endpoint.name };
}

/** Models that cost money per call (counted against the daily limit); Groq's free tier doesn't. */
export const isPaid = (modelID: string) => (MODELS.find((m) => m.id === modelID)?.provider ?? "claude") !== "groq";

/** Whether the model keeps to a JSON schema (OpenRouter's picks and GPT-OSS on Groq do); others get JSON mode. */
export const keepsSchema = (model: Model) => model.provider === "openrouter" || model.id.startsWith("openai/gpt-oss");

/** One call to an OpenAI-compatible chat endpoint (Groq or OpenRouter). Throws a sentence the app can show. */
export async function compatible(provider: Exclude<Provider, "claude">, body: Record<string, unknown>): Promise<{
  message: { content?: string | null; tool_calls?: { id: string; function: { name: string; arguments: string } }[] };
  usage: { prompt_tokens?: number; completion_tokens?: number };
}> {
  const endpoint = await endpointFor(provider);
  const response = await fetch(endpoint.url, {
    method: "POST",
    headers: { Authorization: `Bearer ${endpoint.key}`, "Content-Type": "application/json" },
    body: JSON.stringify(endpoint.model ? { ...body, model: endpoint.model } : body),
  });
  if (response.status === 401) throw new Error(`The ${endpoint.name} key on this server isn't valid.`);
  if (response.status === 402) throw new Error(`Your ${endpoint.name} credit is used up. Top it up, or pick another model in Settings.`);
  if (response.status === 429) {
    throw new Error(provider === "groq" ? "The free Groq limit is used up for now. Try again later or switch model in Settings."
                                         : `${endpoint.name} is busy right now. Try again in a moment.`);
  }
  if (response.status === 413) throw new Error(`That's too long for ${endpoint.name}. Pick Claude for this in Settings, or shorten it.`);
  if (!response.ok) {
    console.error(provider, response.status, await response.text().catch(() => ""));
    throw new Error(`${endpoint.name} returned an error (${response.status}).`);
  }
  const result = await response.json();
  return { message: result?.choices?.[0]?.message ?? {}, usage: result?.usage ?? {} };
}

type Message = { content?: string | null; tool_calls?: { id: string; type?: string; function: { name: string; arguments: string } }[] };

/** Folds an OpenAI-compatible stream's chunks into one message (text and tool calls, which arrive in pieces by index). */
export function foldChunks(chunks: unknown[]): { message: Message; usage: { prompt_tokens?: number; completion_tokens?: number } } {
  let content = "";
  const calls: { id: string; type: string; function: { name: string; arguments: string } }[] = [];
  let usage = {};
  for (const chunk of chunks as { choices?: { delta?: { content?: string; tool_calls?: { index: number; id?: string; function?: { name?: string; arguments?: string } }[] } }[]; usage?: object }[]) {
    if (chunk?.usage) usage = chunk.usage;
    const delta = chunk?.choices?.[0]?.delta;
    if (!delta) continue;
    if (typeof delta.content === "string") content += delta.content;
    for (const piece of delta.tool_calls ?? []) {
      const call = calls[piece.index] ??= { id: "", type: "function", function: { name: "", arguments: "" } };
      if (piece.id) call.id = piece.id;
      if (piece.function?.name) call.function.name += piece.function.name;
      if (piece.function?.arguments) call.function.arguments += piece.function.arguments;
    }
  }
  return { message: { content, ...(calls.length ? { tool_calls: calls.filter(Boolean) } : {}) }, usage };
}

/** Like `compatible`, but streamed: `onText` gets each piece of the answer as it's written. Same errors. */
export async function compatibleStream(provider: Exclude<Provider, "claude">, body: Record<string, unknown>, onText: (text: string) => void) {
  const endpoint = await endpointFor(provider);
  const response = await fetch(endpoint.url, {
    method: "POST",
    headers: { Authorization: `Bearer ${endpoint.key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ...body, ...(endpoint.model ? { model: endpoint.model } : {}), stream: true, stream_options: { include_usage: true } }),
  });
  if (!response.ok || !response.body) {
    // The same sentences as the one-shot call, from its status checks.
    if (response.status === 401) throw new Error(`The ${endpoint.name} key on this server isn't valid.`);
    if (response.status === 402) throw new Error(`Your ${endpoint.name} credit is used up. Top it up, or pick another model in Settings.`);
    if (response.status === 429) throw new Error(provider === "groq" ? "The free Groq limit is used up for now. Try again later or switch model in Settings." : `${endpoint.name} is busy right now. Try again in a moment.`);
    console.error(provider, response.status, await response.text().catch(() => ""));
    throw new Error(`${endpoint.name} returned an error (${response.status}).`);
  }
  const chunks: unknown[] = [];
  let buffer = "";
  const decoder = new TextDecoder();
  for await (const bytes of response.body) {
    buffer += decoder.decode(bytes, { stream: true });
    let end;
    while ((end = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, end).trim();
      buffer = buffer.slice(end + 1);
      if (!line.startsWith("data:")) continue;
      const data = line.slice(5).trim();
      if (data === "[DONE]") continue;
      let chunk;
      try { chunk = JSON.parse(data); } catch { continue; } // a keep-alive or comment line
      // Errors after the stream started come in band, with HTTP 200.
      if (chunk?.error) throw new Error(`${endpoint.name} stopped mid-answer: ${String(chunk.error.message ?? "error").slice(0, 120)}`);
      chunks.push(chunk);
      const text = chunk?.choices?.[0]?.delta?.content;
      if (typeof text === "string" && text) onText(text);
    }
  }
  return foldChunks(chunks);
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
