// © Pexilim
// The survey page calls this once the person presses Send (the answers themselves are already saved). The waitlist hands
// back their answers the first time only, holding MAILER_SECRET; then a beta "yes" gets a thank-you, and the owner
// (NOTIFY_EMAIL, else hello@blinkk.app) gets every answer. Pressing Send again sends nothing new.
import { betaEmail, ownerEmail, sendMail } from "./_email.mjs";

const UPSTREAM = process.env.WAITLIST_URL || "https://wjhvqnynjkljiqdmnyhw.supabase.co/functions/v1/waitlist";

export async function POST(request) {
  const body = await request.json().catch(() => null);
  if (typeof body?.token !== "string" || body.token.length > 64) return Response.json({ error: "Bad request" }, { status: 400 });
  const upstream = await fetch(UPSTREAM, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-blink-mailer": process.env.MAILER_SECRET ?? "" },
    body: JSON.stringify({ action: "finished", token: body.token }),
  }).catch(() => null);
  const answer = upstream ? await upstream.json().catch(() => ({})) : {};
  if (!upstream?.ok) return Response.json({ error: answer.error || "Couldn't reach the waitlist." }, { status: upstream?.status === 404 ? 404 : 502 });
  const mail = answer.mail;
  if (!mail) return Response.json({ ok: true });

  // shortcut: finished_at is set before sending, so a failed batch isn't retried; mark after sending if a send is ever lost.
  const owner = { to: process.env.NOTIFY_EMAIL || "hello@blinkk.app", ...ownerEmail(mail.to, mail.answers) };
  const thanks = mail.answers.beta === "yes" ? [{ to: mail.to, leave: mail.leave, ...betaEmail(process.env.MAIL_SIGNER, mail.leave) }] : [];
  await sendMail([...thanks, owner]);
  return Response.json({ ok: true });
}
