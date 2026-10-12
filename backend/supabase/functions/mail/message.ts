// © Pexilim
// Reading mail safely: headers, encoded words, addresses, a plain-text snippet from MIME; and building a reply draft.
// Everything read here is untrusted data from strangers: it is shortened, cleaned and only ever shown or fenced as data.

export type Headers = Record<string, string>;

/** RFC 5322 headers → lowercase name → unfolded, decoded value (first occurrence wins). */
export function parseHeaders(raw: string): Headers {
  const headers: Headers = {};
  const unfolded = raw.replace(/\r?\n[ \t]+/g, " ");
  for (const line of unfolded.split(/\r?\n/)) {
    const at = line.indexOf(":");
    if (at <= 0) continue;
    const name = line.slice(0, at).trim().toLowerCase();
    if (!(name in headers)) headers[name] = decodeWords(line.slice(at + 1).trim());
  }
  return headers;
}

/** "=?UTF-8?B?...?=" and "=?ISO-8859-1?Q?...?=" → text. Unknown charsets fall back to UTF-8. */
export function decodeWords(value: string): string {
  return value.replace(/=\?([^?]+)\?([BbQq])\?([^?]*)\?=(\s+(?==\?))?/g, (_, charset: string, kind: string, data: string) => {
    let bytes: Uint8Array;
    if (kind.toUpperCase() === "B") {
      try { bytes = Uint8Array.from(atob(data), (c) => c.charCodeAt(0)); } catch { return data; }
    } else {
      bytes = qpBytes(data.replace(/_/g, " "));
    }
    try { return new TextDecoder(charset.toLowerCase()).decode(bytes); } catch { return new TextDecoder().decode(bytes); }
  });
}

function qpBytes(text: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "=" && /^[0-9A-Fa-f]{2}$/.test(text.slice(i + 1, i + 3))) {
      out.push(parseInt(text.slice(i + 1, i + 3), 16));
      i += 2;
    } else if (text[i] === "=" && /^\r?\n/.test(text.slice(i + 1))) {
      i += text[i + 1] === "\r" ? 2 : 1; // soft line break
    } else {
      out.push(...new TextEncoder().encode(text[i]));
    }
  }
  return new Uint8Array(out);
}

/** '"Ada Lovelace" <ada@example.com>' → { name, address }. */
export function parseAddress(value: string): { name: string; address: string } {
  const angle = value.match(/^\s*"?([^"<]*?)"?\s*<([^>]+)>/);
  if (angle) return { name: angle[1].trim(), address: angle[2].trim().toLowerCase() };
  const bare = value.match(/[^\s<>,;]+@[^\s<>,;]+/)?.[0] ?? "";
  return { name: "", address: bare.toLowerCase() };
}

/** A readable plain-text snippet from a (possibly cut-off) MIME body: the first text part, decoded, tags stripped. */
export function plainText(body: string, headers: Headers, max = 1500): string {
  const type = headers["content-type"] ?? "text/plain";
  const boundary = type.match(/boundary="?([^";]+)"?/i)?.[1];
  let text = body;
  let encoding = (headers["content-transfer-encoding"] ?? "").toLowerCase();
  let html = /text\/html/i.test(type);
  if (boundary) {
    const parts = body.split(`--${boundary}`).slice(1);
    const pick = parts.find((p) => /content-type:\s*text\/plain/i.test(p)) ?? parts.find((p) => /content-type:\s*text\/html/i.test(p)) ?? parts[0] ?? "";
    const split = pick.search(/\r?\n\r?\n/);
    const partHeaders = parseHeaders(split >= 0 ? pick.slice(0, split) : "");
    text = split >= 0 ? pick.slice(split).trim() : pick;
    encoding = (partHeaders["content-transfer-encoding"] ?? "").toLowerCase();
    html = /text\/html/i.test(partHeaders["content-type"] ?? "");
    // Nested multipart (e.g. alternative inside mixed): go one level deeper.
    if (/multipart\//i.test(partHeaders["content-type"] ?? "")) return plainText(text, partHeaders, max);
  }
  if (encoding === "base64") {
    const clean = text.replace(/[^A-Za-z0-9+/=]/g, "");
    try { text = new TextDecoder().decode(Uint8Array.from(atob(clean.slice(0, clean.length - (clean.length % 4))), (c) => c.charCodeAt(0))); } catch { /* keep raw */ }
  } else if (encoding === "quoted-printable") {
    text = new TextDecoder().decode(qpBytes(text));
  }
  if (html) text = text.replace(/<(style|script)[\s\S]*?<\/\1>/gi, " ").replace(/<br\s*\/?>|<\/p>/gi, "\n").replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'");
  return text.replace(/\r/g, "").replace(/[ \t]+/g, " ").replace(/\n{3,}/g, "\n\n").trim().slice(0, max);
}

/** Which new UIDs to read this time, and where to resume next time. The first check (last = null) reads the newest
 *  `max`; later checks read the OLDEST `max` new ones and resume right after them, so a burst is never skipped. */
export function uidWindow(found: number[], last: number | null, uidNext: number, max = 15): { take: number[]; last: number } {
  const sorted = [...found].sort((a, b) => a - b);
  if (last === null) return { take: sorted.slice(-max), last: Math.max(uidNext - 1, ...sorted) };
  const pending = sorted.filter((u) => u > last);
  const take = pending.slice(0, max);
  return { take, last: take.length < pending.length ? take[take.length - 1] : Math.max(last, uidNext - 1, ...take) };
}

export type Triage = { uid: number; triage: "important" | "normal" | "newsletter"; reason: string; summary: string; needs_reply: boolean };

/** The model's verdicts, checked: known UIDs only, known labels, short texts. */
export function parseTriage(output: unknown, uids: number[]): Triage[] {
  const list = (output as { messages?: unknown })?.messages;
  if (!Array.isArray(list)) return [];
  return list.flatMap((m) => {
    const { uid, triage, reason, summary, needs_reply } = (m ?? {}) as Record<string, unknown>;
    if (typeof uid !== "number" || !uids.includes(uid) || !["important", "normal", "newsletter"].includes(triage as string)) return [];
    return [{
      uid, triage: triage as Triage["triage"],
      reason: typeof reason === "string" ? reason.slice(0, 300) : "",
      summary: typeof summary === "string" ? summary.slice(0, 600) : "",
      needs_reply: needs_reply === true,
    }];
  });
}

/** "Re: subject", without stacking another "Re:". */
export const replySubject = (subject: string) => {
  const clean = subject.replace(/[\r\n]+/g, " ").trim();
  return /^re:/i.test(clean) ? clean : `Re: ${clean}`;
};

/** A reply as RFC 5322 bytes, for the Drafts folder or for sending: from the owner's address the mail was sent to,
 *  threaded. The body is base64, so no line is ever too long for a mail server. */
export function buildDraft(p: { from: string; to: string; subject: string; body: string; inReplyTo: string; messageId?: string; date?: Date }): Uint8Array {
  const clean = (s: string) => s.replace(/[\r\n]+/g, " ").trim(); // no header injection
  // Non-ASCII as encoded words of 15 characters each on folded lines, so no header line gets too long.
  const encode = (s: string) => /^[\x20-\x7e]*$/.test(s) ? s
    : (Array.from(s).join("").match(/[\s\S]{1,15}/gu) ?? []).map((part) => `=?UTF-8?B?${base64(part)}?=`).join("\r\n ");
  const id = clean(p.inReplyTo);
  const lines = [
    `From: ${clean(p.from)}`,
    `To: ${clean(p.to)}`,
    `Subject: ${encode(replySubject(p.subject))}`,
    `Date: ${(p.date ?? new Date()).toUTCString().replace("GMT", "+0000")}`,
    ...(p.messageId ? [`Message-ID: ${clean(p.messageId)}`] : []),
    ...(id ? [`In-Reply-To: ${id}`, `References: ${id}`] : []),
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=utf-8",
    "Content-Transfer-Encoding: base64",
    "",
    ...(base64(p.body.replace(/\r?\n/g, "\r\n")).match(/.{1,76}/g) ?? []),
  ];
  return new TextEncoder().encode(lines.join("\r\n"));
}

function base64(s: string): string {
  const bytes = new TextEncoder().encode(s);
  let binary = "";
  for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(binary);
}

/** Which of the owner's addresses a message was sent to (so the reply comes from it); the account address otherwise. */
export function replyFrom(to: string, cc: string, account: string, aliases: string[]): string {
  const mine = [account, ...aliases].map((a) => a.trim().toLowerCase()).filter(Boolean);
  // Whole addresses only: the alias "ab@x.com" must not match "dab@x.com".
  const recipients = `${to},${cc}`.split(",").map((a) => parseAddress(a).address).filter(Boolean);
  return mine.find((a) => recipients.includes(a)) ?? account;
}

// Job boards' automated alerts (not recruiters writing personally, who use their own company's address).
const JOB_ALERTS = /(^|[.@])(glassdoor\.com|stepstone\.de|match\.indeed\.com)$|^(jobalerts-noreply|jobs-listings|jobs-noreply)@linkedin\.com$/;
const NO_REPLY = /^(no-?reply|do-?not-?reply|noreply-[^@]*|no-reply-[^@]*)@/;

/** Rules the model can't be talked out of: job-board alerts are never important, and nobody waits for a reply
 *  to an address that can't receive one. */
export function settle(t: Pick<Triage, "triage" | "reason" | "needs_reply">, fromAddr: string): Pick<Triage, "triage" | "reason" | "needs_reply"> {
  const from = fromAddr.toLowerCase();
  if (JOB_ALERTS.test(from)) return { triage: "newsletter", reason: "", needs_reply: false };
  return NO_REPLY.test(from) ? { ...t, needs_reply: false } : t;
}

export type SenderRule = { sender: string; verdict: "important" | "newsletter" };

/** The owner's own verdict for a sender: an exact address first, then "@domain" (which also covers its subdomains). */
export function ruleVerdict(rules: SenderRule[], fromAddr: string): SenderRule["verdict"] | null {
  const from = fromAddr.toLowerCase();
  const exact = rules.find((r) => r.sender === from);
  if (exact) return exact.verdict;
  const domain = from.split("@")[1] ?? "";
  const match = rules.filter((r) => r.sender.startsWith("@")).find((r) => domain === r.sender.slice(1) || domain.endsWith(`.${r.sender.slice(1)}`));
  return match?.verdict ?? null;
}

export type Send = { email_id: string; account: string; from: string; to: string; subject: string; body: string; in_reply_to: string; message_id: string; send_at: string };

const ADDRESS = /^[^\s@<>,;"()]+@[^\s@<>,;"()]+\.[^\s@<>,;"()]+$/;

/** An approved "mail.send" payload, checked again before anything leaves: one plain recipient, a From that is one of
 *  the owner's own addresses, sane sizes. Returns the reason when it isn't sendable. */
export function parseSend(payload: unknown, owned: string[]): Send | string {
  const p = (payload ?? {}) as Record<string, unknown>;
  const text = (k: string, max: number) => typeof p[k] === "string" && (p[k] as string).length <= max ? (p[k] as string) : null;
  const [emailId, account, from, to, subject, body, inReplyTo, messageId, sendAt] =
    [text("email_id", 64), text("account", 20), text("from", 320), text("to", 320), text("subject", 998), text("body", 20000),
     text("in_reply_to", 998), text("message_id", 998), text("send_at", 40)];
  if (emailId === null || !["gmail", "icloud", "uni"].includes(account ?? "")) return "Unknown mailbox.";
  if (!from || !owned.map((a) => a.toLowerCase()).includes(from.toLowerCase())) return "The From address isn't one of yours.";
  if (!to || !ADDRESS.test(to)) return "The recipient's address doesn't look right.";
  if (subject === null || !body?.trim()) return "The mail is empty.";
  if (inReplyTo === null || !messageId || !/^<[^<>\s]+@[^<>\s]+>$/.test(messageId)) return "The mail's ids are missing.";
  if (!sendAt || Number.isNaN(Date.parse(sendAt))) return "The send time is missing.";
  return { email_id: emailId, account: account!, from, to, subject, body, in_reply_to: inReplyTo, message_id: messageId, send_at: sendAt };
}
