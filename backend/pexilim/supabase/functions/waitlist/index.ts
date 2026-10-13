// © Pexilim
// The Blink waitlist (www.blinkk.app). Double opt-in: joining sends a confirmation email (Resend); the person confirms on
// the site's confirm page, and can leave from any email. Answers the same whether an email is new or already listed (no
// way to probe who signed up); a filled honeypot is quietly dropped. Public, so JWT checks are off.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";
import { confirmEmail } from "./email.ts";
import { corsFor, parseAction, parseSignup } from "./input.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const SITE = "https://www.blinkk.app";
// shortcut: one global limit (signups in the last 10 minutes) instead of per-visitor; add a per-IP hash if it's ever hit.
const BURST = 100;

/** Sends through Resend when its key is set (RESEND_API_KEY, RESEND_FROM such as "Blink <hello@blinkk.app>"). */
async function send(to: string, mail: { subject: string; html: string; text: string }, leave: string): Promise<boolean> {
  const key = Deno.env.get("RESEND_API_KEY"), from = Deno.env.get("RESEND_FROM");
  if (!key || !from) return false;
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to, subject: mail.subject, html: mail.html, text: mail.text,
      headers: { "List-Unsubscribe": `<${leave}>` } }),
  });
  if (!res.ok) console.error("resend", res.status, (await res.text()).slice(0, 200));
  return res.ok;
}

Deno.serve(async (req) => {
  const cors = corsFor(req.headers.get("Origin"));
  const json = (status: number, body: Record<string, unknown>) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST only" });
  const body = await req.json().catch(() => null);

  // From the site's confirm and leave pages (a real click, not a link scanner opening the email's link).
  const action = parseAction(body);
  if (action) {
    if (action.kind === "confirm") {
      const { data, error } = await admin.from("waitlist").update({ confirmed_at: new Date().toISOString() })
        .eq("confirm_token", action.token).select("id").maybeSingle();
      if (error) return json(502, { error: "Something went wrong. Try again in a minute." });
      return data ? json(200, { ok: true }) : json(404, { error: "This link has expired. Join again on the site." });
    }
    const { error } = await admin.from("waitlist").delete().eq("unsubscribe", action.token);
    return error ? json(502, { error: "Something went wrong. Try again in a minute." }) : json(200, { ok: true });
  }

  const signup = parseSignup(body);
  if (signup === "bot") return json(200, { ok: true });
  if (typeof signup === "string") return json(400, { error: signup });

  const since = new Date(Date.now() - 10 * 60_000).toISOString();
  const { count, error: countError } = await admin.from("waitlist").select("id", { count: "exact", head: true }).gte("created_at", since);
  if (countError) return json(502, { error: "Something went wrong. Try again in a minute." });
  if ((count ?? 0) >= BURST) return json(429, { error: "Lots of people are joining right now. Try again in a few minutes." });

  // Unconfirmed signups don't linger: a month after joining without confirming, they're gone.
  await admin.from("waitlist").delete().is("confirmed_at", null).lt("created_at", new Date(Date.now() - 30 * 86_400_000).toISOString());

  const { data: row, error } = await admin.from("waitlist").insert(signup).select("confirm_token, unsubscribe").maybeSingle();
  if (error && error.code !== "23505") return json(502, { error: "Something went wrong. Try again in a minute." });
  // Already on the list: same answer, and no second email (a stranger can't make us mail someone over and over).
  if (row) {
    const leave = `${SITE}/leave.html?u=${row.unsubscribe}`;
    await send(signup.email, confirmEmail(`${SITE}/confirm.html?t=${row.confirm_token}`, leave), leave);
  }
  return json(200, { ok: true });
});
