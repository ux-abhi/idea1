// © Pexilim
// The waitlist emails, in the site's look (sent by api/waitlist.mjs): a dark hero with Blink's eyes and one big button,
// then a picture and three small pills instead of paragraphs. Tables and inline styles only, because mail apps ignore
// most CSS; images are hosted on the site; a plain-text part goes with every HTML one.

const SITE = "https://www.blinkk.app";
const FONT = "-apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Helvetica, Arial, sans-serif";

const escape = (s) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

/** A small pill with a mood-coloured dot (wraps to the next line on narrow screens). */
const pill = (dot, label) =>
  `<span style="display:inline-block;margin:0 6px 8px 0;padding:8px 14px;border-radius:999px;background:#f2f2f0;font:500 13px/1 ${FONT};color:#1d1d1f;white-space:nowrap;">` +
  `<span style="display:inline-block;width:8px;height:8px;border-radius:99px;background:${dot};margin-right:7px;vertical-align:1px;"></span>${escape(label)}</span>`;

/** One email: a dark hero (eyes, headline, one line, one button), the film still, pills, and the fine print. */
export function layout(opts) {
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light only"><meta name="supported-color-schemes" content="light only"><title>${escape(opts.title)}</title></head>
<body style="margin:0;padding:0;background:#f2f2f0;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escape(opts.preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f2f2f0;padding:28px 12px;">
<tr><td align="center">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
    <tr><td align="center" style="background:#000;background-image:radial-gradient(120% 90% at 50% 120%,#0a3d7a 0%,#000 60%);border-radius:28px 28px 0 0;padding:0 28px 40px;">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr><td align="center" style="background:#000;border-radius:0 0 22px 22px;padding:14px 26px 12px;">
        <img src="${SITE}/assets/eyes-idle.png" width="96" height="48" alt="Blink's eyes" style="display:block;border:0;width:96px;height:48px;">
      </td></tr></table>
      <h1 style="margin:34px 0 10px;font:700 34px/1.1 ${FONT};color:#fff;letter-spacing:-0.035em;">${escape(opts.title)}</h1>
      <p style="margin:0 0 28px;font:400 17px/1.45 ${FONT};color:#a1a1a6;">${escape(opts.line)}</p>
      <table role="presentation" cellpadding="0" cellspacing="0"><tr><td align="center" style="background:#0a84ff;border-radius:999px;">
        <a href="${escape(opts.button.url)}" style="display:inline-block;padding:16px 34px;font:600 17px/1 ${FONT};color:#fff;text-decoration:none;">${escape(opts.button.label)}</a>
      </td></tr></table>
    </td></tr>
    <tr><td style="background:#fff;border-radius:0 0 28px 28px;padding:28px 28px 26px;">
      <a href="${SITE}/#film" style="text-decoration:none;">
        <img src="${SITE}/assets/blink-film-poster.jpg" width="464" alt="Meet Blink: a 60-second film" style="display:block;width:100%;max-width:464px;height:auto;border:0;border-radius:16px;">
      </a>
      <p style="margin:12px 0 22px;font:600 14px/1.3 ${FONT};"><a href="${SITE}/#film" style="color:#0a66cc;text-decoration:none;">Meet Blink in 60 seconds &rarr;</a></p>
      <div>${opts.pills.map(([dot, label]) => pill(dot, label)).join("")}</div>
    </td></tr>
    <tr><td align="center" style="padding:20px 18px 0;">
      <p style="margin:0 0 8px;font:400 12px/1.6 ${FONT};color:#86868b;">Button not working? <a href="${escape(opts.button.url)}" style="color:#86868b;">Use this link</a>.</p>
      <p style="margin:0;font:400 12px/1.6 ${FONT};color:#86868b;"><b style="color:#1d1d1f;">Blink</b> by Pexilim · <a href="${SITE}" style="color:#86868b;">blinkk.app</a> · <a href="${SITE}/privacy.html#waitlist" style="color:#86868b;">Privacy</a> · <a href="${escape(opts.unsubscribe)}" style="color:#86868b;">Leave the waitlist</a></p>
    </td></tr>
  </table>
</td></tr></table>
</body></html>`;
  const text = `${opts.title}\n\n${opts.line}\n\n${opts.button.label}: ${opts.button.url}\n\nMeet Blink in 60 seconds: ${SITE}/#film\n\n—\nBlink by Pexilim · ${SITE}\nLeave the waitlist: ${opts.unsubscribe}\n`;
  return { html, text };
}

/** One email a few days after someone confirms, asking for the five quick questions (sent once, api/followup.mjs). */
export function followupEmail(surveyUrl, unsubscribeUrl) {
  return {
    subject: "5 quick taps to shape Blink?",
    ...layout({
      preheader: "Under a minute. Your answers decide what we build first.",
      title: "Can you help shape Blink?",
      line: "Five quick taps, under a minute. Your answers decide what we build first, and you can sign up to test Blink early.",
      button: { label: "Answer 5 quick questions", url: surveyUrl },
      pills: [["#0a84ff", "Under a minute"], ["#30d158", "Beta spots open"], ["#ff9f0a", "Every answer read"]],
      unsubscribe: unsubscribeUrl,
    }),
  };
}

/** The thank-you for a beta "yes" (api/survey.mjs). `who` is the person who'll write (MAIL_SIGNER in Vercel), or "We". */
export function betaEmail(who, unsubscribeUrl) {
  const name = who || "We";
  return {
    subject: "You're on the Blink beta list",
    ...layout({
      preheader: `${name} will email you soon to get you set up.`,
      title: "Thank you for joining the beta.",
      line: `We're bringing testers in one at a time, 1:1, so everyone gets a proper setup. ${name} will email you personally soon. Just reply if you have questions.`,
      button: { label: "Meet Blink in 60 seconds", url: `${SITE}/#film` },
      pills: [["#0a84ff", "1:1 setup"], ["#30d158", "Free while testing"], ["#ff9f0a", "Your feedback shapes it"]],
      unsubscribe: unsubscribeUrl,
    }),
  };
}

/** A plain note to the owner (NOTIFY_EMAIL) when someone finishes the survey: their address and every answer. */
export function ownerEmail(to, answers) {
  const rows = [
    ["Email", to], ["Beta", answers.beta ?? "–"], ["Notch MacBook", answers.notch == null ? "–" : answers.notch ? "yes" : "no"],
    ["Would pay", answers.pay ?? "–"], ["First feature", answers.first_feature ?? "–"],
    ["Slips", (answers.slips ?? []).join(", ") || "–"], ["Uses", (answers.uses ?? []).join(", ") || "–"], ["Note", answers.note ?? "–"],
  ];
  return {
    subject: `${answers.beta === "yes" ? "New beta tester" : "New survey answer"}: ${to}`,
    html: `<table style="font:14px/1.5 ${FONT};border-collapse:collapse">${rows.map(([k, v]) =>
      `<tr><td style="padding:4px 14px 4px 0;color:#86868b;vertical-align:top">${k}</td><td style="padding:4px 0">${escape(String(v))}</td></tr>`).join("")}</table>`,
    text: rows.map(([k, v]) => `${k}: ${v}`).join("\n"),
  };
}

/** "Confirm your spot", sent right after someone joins. */
export function confirmEmail(confirmUrl, unsubscribeUrl) {
  return {
    subject: "Confirm your spot on the Blink waitlist",
    ...layout({
      preheader: "One tap and you're on the list.",
      title: "You're almost in.",
      line: "Tap below to confirm it's you. We'll write once Blink is ready for your Mac.",
      button: { label: "Confirm my spot", url: confirmUrl },
      pills: [["#0a84ff", "Ask from your notch"], ["#ff453a", "Mail that sorts itself"], ["#63e6e2", "A clipboard that remembers"]],
      unsubscribe: unsubscribeUrl,
    }),
  };
}

/** Sends emails through Resend in one batch call (up to 100; one call keeps under Resend's per-second limit), each with
 *  its own leave link as List-Unsubscribe. Returns how many were sent; problems are logged, never thrown. */
export async function sendMail(mails) {
  const key = process.env.RESEND_KEY || process.env.RESEND_API_KEY, from = process.env.RESEND_FROM;
  if (!key || !from) { console.error("mail: RESEND_KEY or RESEND_FROM missing; nothing sent"); return 0; }
  if (!mails.length) return 0;
  try {
    const res = await fetch("https://api.resend.com/emails/batch", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify(mails.slice(0, 100).map(({ to, subject, html, text, leave }) =>
        ({ from, to, reply_to: "hello@blinkk.app", subject, html, text, ...(leave && { headers: { "List-Unsubscribe": `<${leave}>` } }) }))),
    });
    if (res.ok) return Math.min(mails.length, 100);
    console.error("resend", res.status, (await res.text()).slice(0, 200));
  } catch (error) {
    console.error("resend", String(error).slice(0, 200));
  }
  return 0;
}
