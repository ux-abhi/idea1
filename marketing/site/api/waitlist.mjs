// © Pexilim
// The waitlist form posts here (same site, so no CORS). This stores the signup on Pexilim's Supabase project, which
// answers this function alone (it holds MAILER_SECRET) with the confirm and leave links, then emails them through Resend
// with the key that lives only in Vercel (RESEND_KEY, RESEND_FROM). The browser only ever gets "ok" or an error.
import { confirmEmail } from "./_email.mjs";

const UPSTREAM = process.env.WAITLIST_URL || "https://wjhvqnynjkljiqdmnyhw.supabase.co/functions/v1/waitlist";
const json = (status, body) => Response.json(body, { status });

async function send(mail) {
  const key = process.env.RESEND_KEY || process.env.RESEND_API_KEY, from = process.env.RESEND_FROM;
  if (!key || !from) { console.error("waitlist: RESEND_KEY or RESEND_FROM missing; signup stored without an email"); return; }
  const { subject, html, text } = confirmEmail(mail.confirm, mail.leave);
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to: mail.to, subject, html, text, headers: { "List-Unsubscribe": `<${mail.leave}>` } }),
  });
  if (!res.ok) console.error("resend", res.status, (await res.text()).slice(0, 200));
}

export async function POST(request) {
  const body = await request.json().catch(() => null);
  if (!body || typeof body !== "object") return json(400, { error: "That doesn't look like an email address." });
  let upstream;
  try {
    upstream = await fetch(UPSTREAM, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-blink-mailer": process.env.MAILER_SECRET ?? "" },
      // Only the fields the waitlist reads; nothing else from the browser goes on.
      body: JSON.stringify({ email: body.email, consent: body.consent, website: body.website, source: body.source }),
    });
  } catch {
    return json(502, { error: "Something went wrong. Try again in a minute." });
  }
  const answer = await upstream.json().catch(() => ({}));
  if (!upstream.ok) return json(upstream.status === 429 ? 429 : upstream.status === 400 ? 400 : 502, { error: answer.error || "Something went wrong. Try again in a minute." });
  if (answer.mail) await send(answer.mail);
  return json(200, { ok: true });
}
