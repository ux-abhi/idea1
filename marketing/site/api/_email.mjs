// © Pexilim
// The waitlist emails, in the site's look (sent by api/waitlist.mjs): a black band with Blink's eyes, a light card, one blue button.
// Tables and inline styles only, because mail apps ignore most CSS; a plain-text part goes with every HTML one.

const SITE = "https://www.blinkk.app";
const FONT = "-apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Helvetica, Arial, sans-serif";

const escape = (s) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

/** One email: a headline, a few short paragraphs, one button, and the fine print with an unsubscribe link. */
export function layout(opts) {
  const p = opts.paragraphs.map((t) =>
    `<p style="margin:0 0 16px;font:400 16px/1.55 ${FONT};color:#3a3a3c;">${escape(t)}</p>`).join("");
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light only"><title>${escape(opts.title)}</title></head>
<body style="margin:0;padding:0;background:#f2f2f0;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escape(opts.preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f2f2f0;padding:32px 12px;">
<tr><td align="center">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;">
    <tr><td align="center" style="background:#000;border-radius:28px 28px 0 0;padding:28px 24px 22px;">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr><td align="center" style="background:#000;border-radius:0 0 18px 18px;">
        <img src="${SITE}/assets/eyes-idle.png" width="120" height="60" alt="Blink's eyes" style="display:block;border:0;width:120px;height:60px;">
      </td></tr></table>
      <p style="margin:14px 0 0;font:600 15px/1 ${FONT};color:#fff;letter-spacing:-0.01em;">Blink</p>
    </td></tr>
    <tr><td style="background:#fff;border-radius:0 0 28px 28px;padding:36px 32px 32px;">
      <h1 style="margin:0 0 18px;font:700 28px/1.15 ${FONT};color:#000;letter-spacing:-0.03em;">${escape(opts.title)}</h1>
      ${p}
      <table role="presentation" cellpadding="0" cellspacing="0" style="margin:8px 0 8px;"><tr><td style="background:#0a84ff;border-radius:999px;">
        <a href="${escape(opts.button.url)}" style="display:inline-block;padding:14px 26px;font:600 16px/1 ${FONT};color:#fff;text-decoration:none;">${escape(opts.button.label)}</a>
      </td></tr></table>
      <p style="margin:18px 0 0;font:400 13px/1.5 ${FONT};color:#6e6e73;">Button not working? Paste this into your browser:<br><a href="${escape(opts.button.url)}" style="color:#0a66cc;word-break:break-all;">${escape(opts.button.url)}</a></p>
    </td></tr>
    <tr><td align="center" style="padding:22px 16px 0;">
      <p style="margin:0;font:400 12px/1.6 ${FONT};color:#6e6e73;">Blink by Pexilim · <a href="${SITE}" style="color:#6e6e73;">blinkk.app</a> · <a href="${SITE}/privacy.html#waitlist" style="color:#6e6e73;">Privacy</a><br>
      Don't want these? <a href="${escape(opts.unsubscribe)}" style="color:#6e6e73;">Leave the waitlist</a>, one click, no questions.</p>
    </td></tr>
  </table>
</td></tr></table>
</body></html>`;
  const text = `${opts.title}\n\n${opts.paragraphs.join("\n\n")}\n\n${opts.button.label}: ${opts.button.url}\n\n—\nBlink by Pexilim · ${SITE}\nLeave the waitlist: ${opts.unsubscribe}\n`;
  return { html, text };
}

/** "Confirm you want Blink news", sent right after someone joins. */
export function confirmEmail(confirmUrl, unsubscribeUrl) {
  return {
    subject: "Confirm your spot on the Blink waitlist",
    ...layout({
      preheader: "One click and you're on the list.",
      title: "One click and you're in.",
      paragraphs: [
        "Thanks for joining the Blink waitlist. Blink is a personal assistant that lives in your MacBook's notch: your day, your mail and your clipboard, one glance away.",
        "Please confirm it was you, so we only email people who asked. We'll write when Blink is ready to download, and not much else.",
      ],
      button: { label: "Confirm my email", url: confirmUrl },
      unsubscribe: unsubscribeUrl,
    }),
  };
}
