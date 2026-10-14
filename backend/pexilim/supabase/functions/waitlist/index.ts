// © Pexilim
// The Blink waitlist (www.blinkk.app). Double opt-in: the site's own function (Vercel, marketing/site/api/waitlist.mjs,
// where the Resend key lives) stores a signup here and gets back the new row's confirm and leave links to email; the
// person confirms on the site's confirm page, and can leave from any email. Only that function, holding MAILER_SECRET,
// ever sees the links, so nobody can confirm someone else's address. Answers the same whether an email is new or already
// listed (no way to probe who signed up); a filled honeypot is quietly dropped. Public, so JWT checks are off.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";
import { corsFor, parseAction, parseAnswer, parseSignup, sameSecret } from "./input.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const SITE = "https://www.blinkk.app";
// shortcut: one global limit (signups in the last 10 minutes) instead of per-visitor; add a per-IP hash if it's ever hit.
const BURST = 100;

Deno.serve(async (req) => {
  const cors = corsFor(req.headers.get("Origin"));
  const json = (status: number, body: Record<string, unknown>) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST only" });
  const body = await req.json().catch(() => null);

  // The five quick questions (survey.html), with the code from the person's own confirm link; only once confirmed.
  const answer = parseAnswer(body);
  const expired = () => json(404, { error: "This link has expired. Confirm your email first, or join again on the site." });
  if (!answer && (body as Record<string, unknown> | null)?.action === "answer") return expired();
  if (answer) {
    // Only what was answered: reopening the page later never blanks earlier answers, and skipping everything stores nothing.
    const given = Object.fromEntries(Object.entries(answer.answers).filter(([, v]) => v !== null && !(Array.isArray(v) && !v.length)));
    if (!Object.keys(given).length) return json(200, { ok: true });
    const { data: person, error: findError } = await admin.from("waitlist").select("id")
      .eq("confirm_token", answer.token).not("confirmed_at", "is", null).maybeSingle();
    if (findError) return json(502, { error: "Something went wrong. Try again in a minute." });
    if (!person) return expired();
    const { error } = await admin.from("waitlist_answer")
      .upsert({ waitlist_id: person.id, ...given, updated_at: new Date().toISOString() });
    return error ? json(502, { error: "Something went wrong. Try again in a minute." }) : json(200, { ok: true });
  }

  // The site's daily mailer: people who confirmed 2 to 30 days ago, haven't answered and haven't been asked yet get one
  // email asking for the five questions. Marked as asked here, so nobody is ever asked twice.
  if ((body as Record<string, unknown> | null)?.action === "followups") {
    if (!sameSecret(req.headers.get("x-blink-mailer"), Deno.env.get("MAILER_SECRET"))) return json(401, { error: "Not allowed" });
    const day = 86_400_000;
    const { data: due, error } = await admin.from("waitlist").select("id, email, confirm_token, unsubscribe")
      .is("followup_at", null).not("confirmed_at", "is", null)
      .lt("confirmed_at", new Date(Date.now() - 2 * day).toISOString()).gt("confirmed_at", new Date(Date.now() - 30 * day).toISOString())
      .limit(50);
    if (error) return json(502, { error: "Couldn't read the waitlist." });
    const ids = (due ?? []).map((p) => p.id);
    if (!ids.length) return json(200, { ok: true, mail: [] });
    const { data: answered, error: readError } = await admin.from("waitlist_answer").select("waitlist_id").in("waitlist_id", ids);
    // Marked as asked before the site sends: if marking fails, nobody is mailed (else they'd get it again every day).
    const { error: markError } = readError ? { error: readError }
      : await admin.from("waitlist").update({ followup_at: new Date().toISOString() }).in("id", ids);
    if (markError) return json(502, { error: "Couldn't update the waitlist." });
    const done = new Set((answered ?? []).map((a) => a.waitlist_id));
    const ask = (due ?? []).filter((p) => !done.has(p.id));
    return json(200, { ok: true, mail: ask.map((p) => ({
      to: p.email, survey: `${SITE}/survey.html?t=${p.confirm_token}`, leave: `${SITE}/leave.html?u=${p.unsubscribe}`,
    })) });
  }

  // From the site's confirm and leave pages (a real click, not a link scanner opening the email's link).
  const action = parseAction(body);
  // The site's survey mailer, once someone presses Send: their answers and address, the first time only, so the site
  // can thank a beta "yes" and tell the owner. Later sends of the same survey get nothing (no repeat emails).
  if (action?.kind === "finished") {
    if (!sameSecret(req.headers.get("x-blink-mailer"), Deno.env.get("MAILER_SECRET"))) return json(401, { error: "Not allowed" });
    const { data: person, error: findError } = await admin.from("waitlist").select("id, email, unsubscribe")
      .eq("confirm_token", action.token).not("confirmed_at", "is", null).maybeSingle();
    if (findError) return json(502, { error: "Something went wrong. Try again in a minute." });
    if (!person) return expired();
    // shortcut: only the first Send mails, so a "maybe" changed to "yes" later gets no thank-you (it shows in the table);
    // add a separate beta_mailed_at if that happens.
    const { data: answers, error } = await admin.from("waitlist_answer").update({ finished_at: new Date().toISOString() })
      .eq("waitlist_id", person.id).is("finished_at", null)
      .select("slips, uses, first_feature, pay, beta, notch, note").maybeSingle();
    if (error) return json(502, { error: "Something went wrong. Try again in a minute." });
    return json(200, { ok: true, mail: answers ? { to: person.email, leave: `${SITE}/leave.html?u=${person.unsubscribe}`, answers } : null });
  }
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
  // A new row, asked for by the site's mailer: hand it the links to email. Anyone else just gets "ok".
  if (row && sameSecret(req.headers.get("x-blink-mailer"), Deno.env.get("MAILER_SECRET"))) {
    return json(200, { ok: true, mail: { to: signup.email, confirm: `${SITE}/confirm.html?t=${row.confirm_token}`, leave: `${SITE}/leave.html?u=${row.unsubscribe}` } });
  }
  return json(200, { ok: true });
});
