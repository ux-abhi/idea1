// © Pexilim
// Dictation and voice commands. Groq's Whisper turns the recording into text (far better than the Mac's own model at
// Hindi and Hinglish), or the Mac sends text it already heard. Then the model the owner picked for voice (Settings ›
// Usage: Claude, OpenRouter, Groq or their own AI) either tidies the text to type, or turns a command into actions.
// The recording goes to Groq and isn't kept here.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { type Action, CLEANUP, COMMAND, firstVideo, parseDictation, parsePlan, whisperHints } from "./input.ts";
import { assistantName, capProblem, FREE_MODELS, lastMonth, pickModel } from "../_shared/models.ts";
import { ownsServer } from "../_shared/owner.ts";
import { secret } from "../_shared/secrets.ts";
import { think } from "./think.ts";

const WHISPER = "whisper-large-v3";
// The fastest free model, unless the owner picks another for voice.
const VOICE_DEFAULT = "openai/gpt-oss-20b";

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/** Search and play become links: a web search, or the first YouTube video for the words (it starts on its own). */
async function links(actions: Action[]): Promise<{ type: "open_app" | "quit_app" | "open_url"; app?: string; url?: string }[]> {
  return await Promise.all(actions.map(async (a) => {
    if (a.type === "open_app" || a.type === "quit_app" || a.type === "open_url") return a;
    const q = encodeURIComponent(a.query);
    if (a.type === "search") return { type: "open_url" as const, url: `https://www.google.com/search?q=${q}`, app: a.app };
    // shortcut: reads YouTube's results page for the first video id (no API key); falls back to the results page if
    // YouTube changes it. Use the YouTube Data API if this starts missing.
    let url = `https://www.youtube.com/results?search_query=${q}`;
    try {
      const page = await fetch(url, { headers: { "Accept-Language": "en" }, signal: AbortSignal.timeout(3000) });
      const id = firstVideo(await page.text());
      if (id) url = `https://www.youtube.com/watch?v=${id}`;
    } catch { /* the results page is still a fine answer */ }
    return { type: "open_url" as const, url, app: a.app };
  }));
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  const url = Deno.env.get("SUPABASE_URL")!;
  const auth = req.headers.get("Authorization") ?? "";
  const db = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  // Who's asking, the request, the settings and the key all at once: each wait here is time spent watching the notch.
  const [{ data: { user } }, body, { data: profile }, { data: spend }, key] = await Promise.all([
    db.auth.getUser(auth.replace(/^Bearer\s+/i, "")), req.json().catch(() => null),
    db.from("profile").select("model_prefs, settings").maybeSingle(),
    db.from("model_usage").select("model, cost_usd, at").gte("at", lastMonth()).gt("cost_usd", 0).not("model", "in", FREE_MODELS),
    secret("GROQ_API_KEY"),
  ]);
  if (!user) return json(401, { error: "signed out" });
  if (!(await ownsServer(user.id))) return json(403, { error: "This server belongs to another account." });

  const parsed = parseDictation(body);
  if (typeof parsed === "string") return json(400, { error: parsed });
  const model = pickModel(profile?.model_prefs, "voice", VOICE_DEFAULT);
  const overCap = capProblem(model, profile?.settings, spend ?? []);
  if (overCap) return json(429, { error: overCap });

  // 1. Speech to text (unless the Mac already did it).
  let raw = parsed.text ?? "", duration = 0;
  if (parsed.audio) {
    if (!key) return json(400, { error: "Add your Groq key in Blink › Settings › Connections, or pick “This Mac only” for speech to text." });
    const form = new FormData();
    form.append("file", new Blob([parsed.audio], { type: "audio/mp4" }), "dictation.m4a");
    form.append("model", WHISPER);
    form.append("response_format", "verbose_json");
    form.append("temperature", "0");
    const hints = whisperHints(parsed.language);
    if (hints.language) form.append("language", hints.language);
    if (hints.prompt && parsed.mode === "type") form.append("prompt", hints.prompt);
    const heard = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
      method: "POST", headers: { Authorization: `Bearer ${key}` }, body: form,
    });
    if (heard.status === 401) return json(502, { error: "The Groq key on this server isn't valid." });
    if (heard.status === 429) return json(502, { error: "The free Groq limit is used up for now. Try again later." });
    if (!heard.ok) {
      console.error("whisper", heard.status, await heard.text().catch(() => ""));
      return json(502, { error: `Groq couldn't hear that (${heard.status}).` });
    }
    ({ text: raw = "", duration = 0 } = await heard.json() as { text?: string; duration?: number });
  }
  raw = raw.trim();
  if (!raw) return json(200, { text: "", actions: [], say: "" });

  // 2. Thinking: a command becomes actions; dictation is tidied (if that fails, the words as heard still go out).
  const fenced = `<text>${raw.replaceAll("<", "\\u003c")}</text>`;
  let text = raw, actions: Awaited<ReturnType<typeof links>> = [], say = "";
  let spent = { inputTokens: 0, outputTokens: 0, usd: 0 };
  try {
    if (parsed.mode === "command") {
      const reply = await think(model, COMMAND, `<name>${assistantName(profile?.settings)}</name>\n${fenced}`, true);
      spent = reply;
      const plan = parsePlan(reply.text);
      actions = await links(plan.actions);
      say = plan.say;
    } else {
      const reply = await think(model, CLEANUP, fenced, false);
      spent = reply;
      const cleaned = reply.text.replaceAll("\\u003c", "<").trim();
      if (cleaned === "EMPTY") text = "";
      else if (cleaned) text = cleaned;
    }
  } catch (error) {
    console.error("voice", error instanceof Error ? error.message : error);
    if (parsed.mode === "command") return json(502, { error: error instanceof Error ? error.message : "Couldn't understand that." });
  }

  // Saved after the reply goes out, so the answer isn't held back by it. Whisper is on Groq's free tier.
  // shortcut: logs $0 for Whisper (Groq's paid price is $0.111 an hour); price it if paid Groq plans ever count.
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const rows = [
    ...(parsed.audio ? [{ owner_id: user.id, feature: "dictate.hear", model: WHISPER, input_tokens: Math.round(duration), output_tokens: 0, cost_usd: 0 }] : []),
    { owner_id: user.id, feature: parsed.mode === "command" ? "voice.command" : "dictate.clean", model: model.id,
      input_tokens: spent.inputTokens, output_tokens: spent.outputTokens, cost_usd: spent.usd },
  ];
  const logged = admin.from("model_usage").insert(rows).then(({ error }) => { if (error) console.error("usage", error.message); });
  // deno-lint-ignore no-explicit-any
  (globalThis as any).EdgeRuntime?.waitUntil(logged);
  return json(200, parsed.mode === "command" ? { text: raw, actions, say } : { text });
});
