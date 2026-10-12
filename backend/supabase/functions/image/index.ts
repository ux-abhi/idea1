// © Pexilim
// Images for posts through Cloudflare Workers AI (FLUX.1 schnell, the owner's free daily allowance): a cover for a post or
// a text-free background for a carousel. The Mac draws any text on top. Returns the JPEG; nothing is stored here.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";
import { DAILY_IMAGES, imagePrompt, parseImageRequest } from "./input.ts";

const MODEL = "@cf/black-forest-labs/flux-1-schnell";

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  const token = Deno.env.get("CLOUDFLARE_API_TOKEN"), account = Deno.env.get("CLOUDFLARE_ACCOUNT_ID");
  if (!token || !account) return json(503, { error: "Add CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID to this server's Edge Function secrets first." });

  const url = Deno.env.get("SUPABASE_URL")!;
  const auth = req.headers.get("Authorization") ?? "";
  const db = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: { user } } = await db.auth.getUser(auth.replace(/^Bearer\s+/i, ""));
  if (!user) return json(401, { error: "signed out" });

  const parsed = parseImageRequest(await req.json().catch(() => null));
  if (typeof parsed === "string") return json(400, { error: parsed });

  // Stay inside the free allowance: at most DAILY_IMAGES a day (UTC, like Cloudflare's reset).
  const midnight = new Date(); midnight.setUTCHours(0, 0, 0, 0);
  const { count } = await db.from("model_usage").select("id", { count: "exact", head: true })
    .eq("feature", "image").gte("at", midnight.toISOString());
  if ((count ?? 0) >= DAILY_IMAGES) return json(429, { error: `Today's ${DAILY_IMAGES} free images are used up. More tomorrow.` });

  let image: string;
  try {
    const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(account)}/ai/run/${MODEL}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ prompt: imagePrompt(parsed), steps: 4 }),
    });
    if (response.status === 401 || response.status === 403) return json(502, { error: "Cloudflare didn't accept the token. Check it in Settings › Connections." });
    if (response.status === 429) return json(429, { error: "Cloudflare's free image allowance is used up for today." });
    if (!response.ok) {
      console.error("cloudflare", response.status, await response.text().catch(() => ""));
      return json(502, { error: `Cloudflare returned an error (${response.status}).` });
    }
    const result = await response.json();
    image = String(result?.result?.image ?? result?.image ?? "");
    if (!/^[A-Za-z0-9+/=]{1000,}$/.test(image)) return json(502, { error: "Cloudflare didn't return an image. Try again." });
  } catch (error) {
    console.error("cloudflare", error);
    return json(502, { error: "Couldn't reach Cloudflare. Try again in a minute." });
  }

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  await admin.from("model_usage").insert({ owner_id: user.id, feature: "image", model: MODEL, input_tokens: 0, output_tokens: 0, cost_usd: 0 });
  return json(200, { image }); // base64 JPEG
});
