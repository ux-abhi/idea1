// © Pexilim
// Once a day (Vercel Cron, vercel.json): asks the waitlist for people who confirmed 2–30 days ago and haven't answered
// the five questions yet, then emails each one the survey link, once. The waitlist marks them as asked, so a rerun
// never mails anyone twice. Only Vercel's cron may call this (CRON_SECRET, which Vercel sends as a Bearer token).
import { followupEmail, sendMail } from "./_email.mjs";

const UPSTREAM = process.env.WAITLIST_URL || "https://wjhvqnynjkljiqdmnyhw.supabase.co/functions/v1/waitlist";

export async function GET(request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) return new Response("Not allowed", { status: 401 });

  const upstream = await fetch(UPSTREAM, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-blink-mailer": process.env.MAILER_SECRET ?? "" },
    body: JSON.stringify({ action: "followups" }),
  }).catch(() => null);
  const answer = upstream ? await upstream.json().catch(() => ({})) : {};
  if (!upstream?.ok) return Response.json({ error: answer.error || "waitlist unreachable" }, { status: 502 });

  // shortcut: people are marked as asked before this sends, so a failed batch isn't retried; mark after sending if that ever matters.
  const sent = await sendMail((answer.mail ?? []).map((m) => ({ to: m.to, leave: m.leave, ...followupEmail(m.survey, m.leave) })));
  return Response.json({ ok: true, sent });
}
