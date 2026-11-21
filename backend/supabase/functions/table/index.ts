// © Pexilim
// AI on Space tables: "plan" shapes a table from a sentence, "rows" turns pasted text into rows. Returns a proposal the
// owner previews in the app; nothing is written here except the AI usage record.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { parsePlan, parseRequest, parseRows, PLAN_SYSTEM, planPrompt, ROWS_SYSTEM, rowsPrompt } from "./plan.ts";
import { capProblem, FREE_MODELS, lastMonth, pickModel } from "../_shared/models.ts";
import { ownsServer } from "../_shared/owner.ts";
import { think } from "../_shared/think.ts";

const CHAT_DEFAULT = Deno.env.get("BLINK_CHAT_MODEL");

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  const url = Deno.env.get("SUPABASE_URL")!;
  const auth = req.headers.get("Authorization") ?? "";
  const db = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: { user } } = await db.auth.getUser(auth.replace(/^Bearer\s+/i, ""));
  if (!user) return json(401, { error: "signed out" });
  if (!(await ownsServer(user.id))) return json(403, { error: "This server belongs to another account." });

  const [parsed, { data: profile }, { data: spend }] = await Promise.all([
    req.json().catch(() => null).then(parseRequest),
    db.from("profile").select("model_prefs, settings").maybeSingle(),
    db.from("model_usage").select("model, cost_usd, at").gte("at", lastMonth()).gt("cost_usd", 0).not("model", "in", FREE_MODELS),
  ]);
  if (typeof parsed === "string") return json(400, { error: parsed });
  const model = pickModel(profile?.model_prefs, "chat", CHAT_DEFAULT);
  const overCap = capProblem(model, profile?.settings, spend ?? []);
  if (overCap) return json(429, { error: overCap });

  let reply;
  try {
    reply = parsed.action === "plan"
      ? await think(model, PLAN_SYSTEM, planPrompt(parsed), true, 2000)
      : await think(model, ROWS_SYSTEM, rowsPrompt(parsed), true, 8000);
  } catch (error) {
    return json(502, { error: error instanceof Error ? error.message : "The AI couldn't answer. Try again." });
  }
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  await admin.from("model_usage").insert({ owner_id: user.id, feature: `table.${parsed.action}`, model: model.id,
    input_tokens: reply.inputTokens, output_tokens: reply.outputTokens, cost_usd: reply.usd });

  if (parsed.action === "plan") {
    const plan = parsePlan(reply.text, parsed.columns);
    return typeof plan === "string" ? json(422, { error: plan }) : json(200, { plan });
  }
  const rows = parseRows(reply.text, parsed.columns);
  return typeof rows === "string" ? json(422, { error: rows }) : json(200, { rows });
});
