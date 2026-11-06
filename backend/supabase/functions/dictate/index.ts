// © Pexilim
// Dictation through Groq, the way FreeFlow does it: Whisper large-v3 turns the recording into text (far better than
// the Mac's own model at Hindi and Hinglish), then a small Groq model removes fillers and fixes punctuation. The
// recording is sent to Groq and not kept here.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { CLEANUP, parseDictation, whisperHints } from "./input.ts";
import { compatible, MODELS } from "../_shared/models.ts";
import { ownsServer } from "../_shared/owner.ts";
import { secret } from "../_shared/secrets.ts";

const WHISPER = "whisper-large-v3";
const CLEANER = MODELS.find((m) => m.id === "openai/gpt-oss-20b")!;

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  const url = Deno.env.get("SUPABASE_URL")!;
  const auth = req.headers.get("Authorization") ?? "";
  const db = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: { user } } = await db.auth.getUser(auth.replace(/^Bearer\s+/i, ""));
  if (!user) return json(401, { error: "signed out" });
  if (!(await ownsServer(user.id))) return json(403, { error: "This server belongs to another account." });

  const parsed = parseDictation(await req.json().catch(() => null));
  if (typeof parsed === "string") return json(400, { error: parsed });
  const key = await secret("GROQ_API_KEY");
  if (!key) return json(400, { error: "Add your Groq key in Blink › Settings › Connections first." });

  // 1. Speech to text.
  const form = new FormData();
  form.append("file", new Blob([parsed.audio], { type: "audio/mp4" }), "dictation.m4a");
  form.append("model", WHISPER);
  form.append("response_format", "verbose_json");
  form.append("temperature", "0");
  const hints = whisperHints(parsed.language);
  if (hints.language) form.append("language", hints.language);
  if (hints.prompt) form.append("prompt", hints.prompt);
  const heard = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
    method: "POST", headers: { Authorization: `Bearer ${key}` }, body: form,
  });
  if (heard.status === 401) return json(502, { error: "The Groq key on this server isn't valid." });
  if (heard.status === 429) return json(502, { error: "The free Groq limit is used up for now. Try again later." });
  if (!heard.ok) {
    console.error("whisper", heard.status, await heard.text().catch(() => ""));
    return json(502, { error: `Groq couldn't hear that (${heard.status}).` });
  }
  const { text: raw = "", duration = 0 } = await heard.json() as { text?: string; duration?: number };
  if (!raw.trim()) return json(200, { text: "" });

  // 2. Clean-up; if it fails, the words as heard are still better than nothing.
  let text = raw.trim(), usage: { prompt_tokens?: number; completion_tokens?: number } = {};
  try {
    const result = await compatible("groq", {
      model: CLEANER.id,
      temperature: 0.1,
      reasoning_effort: "low",
      messages: [
        { role: "system", content: CLEANUP },
        { role: "user", content: `<text>${raw.replaceAll("<", "\\u003c")}</text>` },
      ],
    });
    const cleaned = String(result.message.content ?? "").replaceAll("\\u003c", "<").trim();
    if (cleaned === "EMPTY") text = "";
    else if (cleaned) text = cleaned;
    usage = result.usage;
  } catch (error) {
    console.error("cleanup", error instanceof Error ? error.message : error);
  }

  // Logged like the other Groq calls: on Groq's free tier, so no cost against the paid limits.
  // shortcut: logs $0 for Whisper (Groq's paid price is $0.111 an hour); add it to MODELS with a price if paid Groq
  // plans ever count against the limits.
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  await admin.from("model_usage").insert([
    { owner_id: user.id, feature: "dictate.hear", model: WHISPER, input_tokens: Math.round(duration), output_tokens: 0, cost_usd: 0 },
    { owner_id: user.id, feature: "dictate.clean", model: CLEANER.id, input_tokens: usage.prompt_tokens ?? 0,
      output_tokens: usage.completion_tokens ?? 0, cost_usd: 0 },
  ]);
  return json(200, { text });
});
