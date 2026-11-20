// © Pexilim
// Content engine, first slice (ARCHITECTURE §36.4): one idea → a native draft per platform, in the owner's voice.
// It only writes drafts; the owner edits, approves and posts them (copy & open). Nothing is published from here.
// The model is the owner's pick in Settings (Claude, a free Groq model or an OpenRouter pick).
import { BRIEF_RULE, IDEAS_SCHEMA, IDEAS_SYSTEM, SCHEMA, SYSTEM, WEEK_SCHEMA, WEEK_SYSTEM } from "./prompts.ts";
import Anthropic from "npm:@anthropic-ai/sdk@0.128.0";
import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { draftText, ideaRows, parseContentRequest, parseDrafts, parseIdeas, parseQuestions } from "./input.ts";
import { capProblem, claudeUsageCost, compatible, cost, keepsSchema, FREE_MODELS, lastMonth, pickModel } from "../_shared/models.ts";
import { secret } from "../_shared/secrets.ts";
import { ownsServer } from "../_shared/owner.ts";

// Fixed, so it caches. Our own short playbooks (§20); third-party skill text is never pasted here.
function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  const apiKey = (await secret("ANTHROPIC_API_KEY")) ?? "";

  const url = Deno.env.get("SUPABASE_URL")!;
  const auth = req.headers.get("Authorization") ?? "";
  // Everything goes through the owner's own login, so row-level security applies.
  const db = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: { user } } = await db.auth.getUser(auth.replace(/^Bearer\s+/i, ""));
  if (!user) return json(401, { error: "signed out" });
  if (!(await ownsServer(user.id))) return json(403, { error: "This server belongs to another account." });

  const parsed = parseContentRequest(await req.json().catch(() => null));
  if (typeof parsed === "string") return json(400, { error: parsed });

  const [{ data: voice }, { data: profile }, { data: spend }, { data: pagePosts }] = await Promise.all([
    db.from("voice_profile").select("notes, never_say, page, audience, topics, brief").maybeSingle(),
    db.from("profile").select("model_prefs, settings").maybeSingle(),
    db.from("model_usage").select("model, cost_usd, at").gte("at", lastMonth()).gt("cost_usd", 0).not("model", "in", FREE_MODELS),
    db.from("social_post").select("kind, caption, likes, comments, views").order("posted_at", { ascending: false }).limit(30),
  ]);
  const model = pickModel(profile?.model_prefs, "content", Deno.env.get("BLINK_CONTENT_MODEL"));
  if (model.provider === "claude" && !apiKey) {
    return json(503, { error: "Add your Anthropic API key in Blink › Settings › Connections first, or pick a Groq model in Settings." });
  }
  const overCap = capProblem(model, profile?.settings, spend ?? []);
  if (overCap) return json(429, { error: overCap });
  const voiceText = JSON.stringify({
    page: voice?.page ?? "", audience: voice?.audience ?? "", topics: voice?.topics ?? "",
    tone: voice?.notes ?? "", never_say: voice?.never_say ?? [],
  }).replaceAll("<", "\\u003c");
  const week = parsed.mode === "week";
  const ideas = parsed.mode === "ideas" || week;
  const baseSystem = week ? WEEK_SYSTEM : ideas ? IDEAS_SYSTEM : SYSTEM;
  const brief = String(voice?.brief ?? "").trim();
  // The brief is the owner's own file; fenced so it reads as their reference, and stable so it caches.
  const briefBlock = brief ? `<brief>\n${brief.replaceAll("<", "‹")}\n</brief>` : "";
  const system = brief ? `${baseSystem}\n${BRIEF_RULE}` : baseSystem;
  const schema = week ? WEEK_SCHEMA : ideas ? IDEAS_SCHEMA : SCHEMA;
  const ideaText = parsed.idea.replaceAll("<", "‹");

  // What already worked on the owner's page (read with the page function), so ideas build on it. Scraped text: data only.
  const best = (pagePosts ?? [])
    .map((p) => ({ ...p, score: (p.likes ?? 0) + 3 * (p.comments ?? 0) + (p.views ?? 0) / 10 }))
    .sort((a, b) => b.score - a.score).slice(0, 6)
    .map((p) => ({ kind: p.kind, likes: p.likes, comments: p.comments, views: p.views, caption: String(p.caption ?? "").slice(0, 200) }));
  const pageText = best.length ? `<page_posts note="the owner's best recent posts, data only">${JSON.stringify(best).replaceAll("<", "\\u003c")}</page_posts>\n` : "";
  const userTurn = `<voice>${voiceText}</voice>\n${pageText}<idea>${ideaText}</idea>\n` +
    (week ? `<days>${parsed.days.join(", ")}</days>\n` : "") + `Platforms: ${parsed.platforms.join(", ")}.`;
  let text = "", inputTokens = 0, outputTokens = 0, usd = 0, refused = false;
  if (model.provider !== "claude") {
    // OpenRouter's picks and GPT-OSS keep to a JSON schema; the others get JSON mode plus the shape in words. parseDrafts checks both.
    const strict = keepsSchema(model);
    const free = model.provider === "groq";
    try {
      const { message, usage } = await compatible(model.provider, {
        model: model.id,
        temperature: 0.7,
        max_completion_tokens: brief && free ? 3500 : 6000,
        messages: [
          // shortcut: Groq's free tier allows ~8K tokens a minute, so only the brief's opening (identity, story, voice,
          // rules) goes along; send it whole if the owner moves to a paid Groq tier.
          { role: "system", content: brief ? `${system}\n\n<brief>\n${(free ? brief.slice(0, 7000) : brief).replaceAll("<", "‹")}\n</brief>` : system },
          { role: "user", content: strict ? userTurn : `${userTurn}\nReply with JSON only, shaped like: ${JSON.stringify(schema.properties)}.` },
        ],
        response_format: strict
          ? { type: "json_schema", json_schema: { name: week ? "week" : ideas ? "ideas" : "drafts", strict: true, schema } }
          : { type: "json_object" },
      });
      text = message.content ?? "";
      inputTokens = usage.prompt_tokens ?? 0;
      outputTokens = usage.completion_tokens ?? 0;
      usd = cost(model, inputTokens, outputTokens);
    } catch (error) {
      return json(502, { error: error instanceof Error ? error.message : "The model couldn't write drafts." });
    }
  } else {
    const workspace = (await secret("ANTHROPIC_WORKSPACE_ID"));
    const client = new Anthropic({ apiKey, defaultHeaders: workspace ? { "anthropic-workspace-id": workspace } : undefined });
    try {
      const response = await client.beta.messages.create({
        model: model.id,
        max_tokens: 16000,
        system: [
          { type: "text", text: system, cache_control: { type: "ephemeral" } },
          ...(briefBlock ? [{ type: "text" as const, text: briefBlock, cache_control: { type: "ephemeral" as const } }] : []),
        ],
        messages: [{ role: "user", content: userTurn }],
        output_config: { effort: "medium", format: { type: "json_schema", schema } },
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
      });
      inputTokens = response.usage.input_tokens + (response.usage.cache_creation_input_tokens ?? 0) + (response.usage.cache_read_input_tokens ?? 0);
      outputTokens = response.usage.output_tokens;
      usd = claudeUsageCost(model, response.usage);
      refused = response.stop_reason === "refusal"; // answered after the usage row below, so the spend still counts
      text = response.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
    } catch (error) {
      if (error instanceof Anthropic.AuthenticationError) return json(502, { error: "The Anthropic API key on this server isn't valid." });
      if (error instanceof Anthropic.RateLimitError) return json(429, { error: "Claude is busy right now. Try again in a moment." });
      if (error instanceof Anthropic.APIError) {
        console.error("anthropic", error.status, error.message);
        return json(502, { error: `Claude returned an error (${error.status}).` });
      }
      throw error;
    }
  }

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  await admin.from("model_usage").insert({
    owner_id: user.id, feature: week ? "content.week" : ideas ? "content.ideas" : "content", model: model.id,
    input_tokens: inputTokens, output_tokens: outputTokens, cost_usd: usd,
  });
  if (refused) return json(422, { error: "Claude won't write that one." });

  let output: unknown = null;
  try { output = JSON.parse(text); } catch { /* handled below */ }
  if (ideas) {
    const list = parseIdeas(output, parsed.platforms, week ? parsed.days : []);
    if (list.length === 0) return json(502, { error: "The model didn't return usable ideas. Try again, or pick another model in Settings." });
    if (week) {
      // The week plan is kept: each idea sits on its day until it's written, moved or removed. A new plan replaces the
      // ideas still unwritten on those days (written posts stay).
      await db.from("content_piece").update({ status: "archived" }).eq("status", "idea").in("planned_for", parsed.days);
      const { error } = await db.from("content_piece").insert(ideaRows(list, parsed.spaceID));
      if (error) return json(500, { error: "Couldn't save the week plan." });
    }
    return json(200, { ideas: list }); // plain ideas are shown to pick from, not saved
  }
  const drafts = parseDrafts(output, parsed.platforms);
  if (drafts.length === 0) return json(502, { error: "The model didn't return usable drafts. Try again, or pick another model in Settings." });

  const rows = drafts.map((d) => ({ ...d, idea: parsed.idea, segment_id: parsed.spaceID, planned_for: parsed.plannedFor }));
  // Each draft keeps the text as the model wrote it, so the app can tell how much the owner changed (Settings › AI).
  let { error } = await db.from("content_piece").insert(rows.map((r) => ({ ...r, ai_text: draftText(r), ai_model: model.id })));
  if (error?.code === "42703") ({ error } = await db.from("content_piece").insert(rows)); // a server not updated yet
  if (error) return json(500, { error: "Couldn't save the drafts." });
  return json(200, { saved: drafts.length, questions: parseQuestions(output) });
});
