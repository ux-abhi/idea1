// © Pexilim
// Settings › Connections: is each key on this server present and accepted? Each check uses a free, read-only call
// (a model list or an account lookup); keys never leave the server and nothing is spent.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

type Status = "ok" | "missing" | "rejected" | "unreachable";

async function check(secret: string | undefined, request: (key: string) => Promise<Response>): Promise<Status> {
  if (!secret) return "missing";
  try {
    const response = await request(secret);
    if (response.ok) return "ok";
    return response.status === 401 || response.status === 403 ? "rejected" : "unreachable";
  } catch {
    return "unreachable";
  }
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });
  const { data: { user } } = await db.auth.getUser((req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, ""));
  if (!user) return json(401, { error: "signed out" });

  const account = Deno.env.get("CLOUDFLARE_ACCOUNT_ID");
  const openrouterKey = Deno.env.get("OPENROUTER_API_KEY");
  const [anthropic, groq, apify, cloudflare, openrouter, credit] = await Promise.all([
    check(Deno.env.get("ANTHROPIC_API_KEY"), (key) => fetch("https://api.anthropic.com/v1/models?limit=1", {
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01",
                 ...(Deno.env.get("ANTHROPIC_WORKSPACE_ID") ? { "anthropic-workspace-id": Deno.env.get("ANTHROPIC_WORKSPACE_ID")! } : {}) },
    })),
    check(Deno.env.get("GROQ_API_KEY"), (key) => fetch("https://api.groq.com/openai/v1/models", { headers: { Authorization: `Bearer ${key}` } })),
    check(Deno.env.get("APIFY_TOKEN"), (key) => fetch("https://api.apify.com/v2/users/me", { headers: { Authorization: `Bearer ${key}` } })),
    account
      ? check(Deno.env.get("CLOUDFLARE_API_TOKEN"), (key) => fetch(
          `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(account)}/ai/models/search?per_page=1`,
          { headers: { Authorization: `Bearer ${key}` } }))
      : Promise.resolve<Status>("missing"),
    check(openrouterKey, (key) => fetch("https://openrouter.ai/api/v1/key", { headers: { Authorization: `Bearer ${key}` } })),
    // What's left of the OpenRouter credit (the key's own limit, if it has one), so the owner sees the $ before picking.
    (async () => {
      if (!openrouterKey) return null;
      try {
        const r = await fetch("https://openrouter.ai/api/v1/credits", { headers: { Authorization: `Bearer ${openrouterKey}` } });
        const d = (await r.json())?.data;
        const left = Number(d?.total_credits) - Number(d?.total_usage);
        return Number.isFinite(left) ? Math.max(0, Math.round(left * 100) / 100) : null;
      } catch { return null; }
    })(),
  ]);
  return json(200, { anthropic, groq, apify, cloudflare, openrouter, openrouter_credit: credit === null ? "" : String(credit) });
});
