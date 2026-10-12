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

/** A reply as RFC 5322 bytes for the Drafts folder: from the owner's address the mail was sent to, threaded. */
export function buildDraft(p: { from: string; to: string; subject: string; body: string; inReplyTo: string; date?: Date }): Uint8Array {
  const clean = (s: string) => s.replace(/[\r\n]+/g, " ").trim(); // no header injection
  const subject = /^re:/i.test(p.subject.trim()) ? clean(p.subject) : `Re: ${clean(p.subject)}`;
  const encode = (s: string) => /^[\x20-\x7e]*$/.test(s) ? s : `=?UTF-8?B?${btoa(String.fromCharCode(...new TextEncoder().encode(s)))}?=`;
  const id = clean(p.inReplyTo);
  const lines = [
    `From: ${clean(p.from)}`,
    `To: ${clean(p.to)}`,
    `Subject: ${encode(subject)}`,
    `Date: ${(p.date ?? new Date()).toUTCString().replace("GMT", "+0000")}`,
    ...(id ? [`In-Reply-To: ${id}`, `References: ${id}`] : []),
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=utf-8",
    "Content-Transfer-Encoding: 8bit",
    "",
    p.body.replace(/\r?\n/g, "\r\n"),
  ];
  return new TextEncoder().encode(lines.join("\r\n"));
}

/** Which of the owner's addresses a message was sent to (so the reply comes from it); the account address otherwise. */
export function replyFrom(to: string, cc: string, account: string, aliases: string[]): string {
  const mine = [account, ...aliases].map((a) => a.trim().toLowerCase()).filter(Boolean);
  const all = `${to},${cc}`.toLowerCase();
  return mine.find((a) => all.includes(a)) ?? account;
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
