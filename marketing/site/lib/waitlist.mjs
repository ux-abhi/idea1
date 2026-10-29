// © Pexilim
// The waitlist form posts here (same site, so no CORS). This stores the signup on Pexilim's Supabase project, which
// answers this function alone (it holds MAILER_SECRET) with the confirm and leave links, then emails them through Resend
// with the key that lives only in Vercel (RESEND_KEY, RESEND_FROM). The browser only ever gets "ok" or an error.
import { confirmEmail, sendMail } from "./_email.mjs";

const UPSTREAM = process.env.WAITLIST_URL || "https://wjhvqnynjkljiqdmnyhw.supabase.co/functions/v1/waitlist";
const json = (status, body) => Response.json(body, { status });

const send = (mail) => sendMail([{ to: mail.to, leave: mail.leave, ...confirmEmail(mail.confirm, mail.leave) }]);

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
  // Anything but a bad address or the burst limit is our fault (often a wrong MAILER_SECRET): say so in the logs.
  if (!upstream.ok && upstream.status !== 400 && upstream.status !== 429) console.error("waitlist upstream", upstream.status, answer.error);
  if (!upstream.ok) return json(upstream.status === 429 ? 429 : upstream.status === 400 ? 400 : 502, { error: answer.error || "Something went wrong. Try again in a minute." });
  // No email went out: say so, so the person tries again instead of waiting for a link that never comes.
  if (answer.mail && !(await send(answer.mail))) {
    console.error("waitlist: confirmation email not sent");
    return json(502, { error: "We couldn't send your confirmation email. Try again in a minute." });
  }
  return json(200, { ok: true });
}
