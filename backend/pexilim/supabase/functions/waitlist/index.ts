// © Pexilim
// The Blink waitlist: blink.pexilim.com posts an email here. It answers the same way whether the email is new or already
// on the list (no way to probe who signed up), and a filled honeypot is quietly dropped. Public, so JWT checks are off.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";
import { corsFor, parseSignup } from "./input.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
// shortcut: one global limit (signups in the last 10 minutes) instead of per-visitor; add a per-IP hash if it's ever hit.
const BURST = 100;

Deno.serve(async (req) => {
  const cors = corsFor(req.headers.get("Origin"));
  const json = (status: number, body: Record<string, unknown>) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const signup = parseSignup(await req.json().catch(() => null));
  if (signup === "bot") return json(200, { ok: true });
  if (typeof signup === "string") return json(400, { error: signup });

  const since = new Date(Date.now() - 10 * 60_000).toISOString();
  const { count, error: countError } = await admin.from("waitlist").select("id", { count: "exact", head: true }).gte("created_at", since);
  if (countError) return json(502, { error: "Something went wrong. Try again in a minute." });
  if ((count ?? 0) >= BURST) return json(429, { error: "Lots of people are joining right now. Try again in a few minutes." });

  const { error } = await admin.from("waitlist").upsert(signup, { onConflict: "email", ignoreDuplicates: true });
  if (error) return json(502, { error: "Something went wrong. Try again in a minute." });
  return json(200, { ok: true });
});
