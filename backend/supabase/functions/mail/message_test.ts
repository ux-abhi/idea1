// © Pexilim
import { buildDraft, parseAddress, parseHeaders, parseTriage, plainText, replyFrom, ruleVerdict, parseSend, settle } from "./message.ts";

Deno.test("headers unfold and decode encoded words", () => {
  const h = parseHeaders("Subject: =?UTF-8?B?SW50ZXJ2aWV3IOKAkyBUZWFtVmlld2Vy?=\r\nFrom: \"Wolfram\"\r\n <w@teamviewer.com>\r\nTo: hello@pexilim.com\r\n");
  if (h.subject !== "Interview – TeamViewer" || parseAddress(h.from).address !== "w@teamviewer.com" || parseAddress(h.from).name !== "Wolfram") {
    throw new Error(JSON.stringify(h));
  }
  if (parseAddress("ada@example.com").address !== "ada@example.com") throw new Error("bare address");
});

Deno.test("plain text comes from the text part of multipart mail, decoded, without HTML", () => {
  const boundary = "XYZ";
  const body = `--XYZ\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nHallo Abhishek,=0Asee you Monday=21\r\n--XYZ\r\nContent-Type: text/html\r\n\r\n<p>ignored</p>\r\n--XYZ--`;
  const text = plainText(body, { "content-type": `multipart/alternative; boundary="${boundary}"` });
  if (text !== "Hallo Abhishek,\nsee you Monday!") throw new Error(JSON.stringify(text));
  if (plainText("<style>x{}</style><p>Hi &amp; bye</p>", { "content-type": "text/html" }) !== "Hi & bye") throw new Error("html");
  if (plainText("SGVsbG8gd29ybGQ=", { "content-transfer-encoding": "base64" }) !== "Hello world") throw new Error("base64");
});

Deno.test("triage keeps only known messages and labels", () => {
  const t = parseTriage({ messages: [
    { uid: 1, triage: "important", reason: "Interview invite", summary: "s", needs_reply: true },
    { uid: 2, triage: "urgent!!", reason: "", summary: "", needs_reply: false },
    { uid: 99, triage: "normal", reason: "", summary: "", needs_reply: false },
  ] }, [1, 2]);
  if (t.length !== 1 || !t[0].needs_reply) throw new Error(JSON.stringify(t));
});

Deno.test("drafts are threaded, from the right address, and can't smuggle headers", () => {
  const raw = new TextDecoder().decode(buildDraft({
    from: "hello@pexilim.com", to: "w@teamviewer.com\r\nBcc: evil@x.com", subject: "Interview\nBcc: evil@x.com",
    body: "Hi Wolfram,\nThanks.", inReplyTo: "<abc@tv.com>", date: new Date("2026-10-12T10:00:00Z"),
  }));
  const body = atob(raw.split("\r\n\r\n")[1].replaceAll("\r\n", ""));
  if (/\r\nBcc:/i.test(raw) || !raw.includes("In-Reply-To: <abc@tv.com>") || !raw.includes("Subject: Re: Interview Bcc") || body !== "Hi Wolfram,\r\nThanks.") {
    throw new Error(raw);
  }
  if (replyFrom("Hello <hello@uxabhi.com>", "", "me@icloud.com", ["hello@pexilim.com", "hello@uxabhi.com"]) !== "hello@uxabhi.com") throw new Error("alias");
  if (replyFrom("other@x.com", "", "me@icloud.com", []) !== "me@icloud.com") throw new Error("fallback");
});

Deno.test("job alerts and no-reply senders are settled in code", () => {
  const hot = { triage: "important" as const, reason: "Job posting", needs_reply: true };
  if (settle(hot, "noreply@glassdoor.com").triage !== "newsletter") throw new Error("glassdoor");
  if (settle(hot, "info@jobagent.stepstone.de").triage !== "newsletter") throw new Error("stepstone");
  if (settle(hot, "jobalerts-noreply@linkedin.com").triage !== "newsletter") throw new Error("linkedin");
  if (settle(hot, "recruiter@teamviewer.com").triage !== "important") throw new Error("a real recruiter stays important");
  if (settle(hot, "no-reply@accounts.google.com").needs_reply) throw new Error("no-reply can't need a reply");
  if (!settle(hot, "paresh@gmail.com").needs_reply) throw new Error("people keep needs_reply");
});

Deno.test("the owner's sender rules: exact address first, then the domain and its subdomains", () => {
  const rules = [{ sender: "@glassdoor.com", verdict: "newsletter" as const }, { sender: "boss@glassdoor.com", verdict: "important" as const }];
  if (ruleVerdict(rules, "Boss@glassdoor.com") !== "important") throw new Error("exact");
  if (ruleVerdict(rules, "noreply@mail.glassdoor.com") !== "newsletter") throw new Error("subdomain");
  if (ruleVerdict(rules, "x@notglassdoor.com") !== null) throw new Error("lookalike domain matched");
});

Deno.test("a send is checked before it leaves", () => {
  const ok = { email_id: "e1", account: "icloud", from: "hello@pexilim.com", to: "w@tv.com", subject: "Re: Hi", body: "Thanks",
    in_reply_to: "<a@tv.com>", message_id: "<b@pexilim.com>", send_at: "2026-10-15T07:00:00Z" };
  const owned = ["me@icloud.com", "hello@pexilim.com"];
  if (typeof parseSend(ok, owned) === "string") throw new Error("valid send refused");
  if (typeof parseSend({ ...ok, from: "ceo@bank.com" }, owned) !== "string") throw new Error("foreign From accepted");
  if (typeof parseSend({ ...ok, to: "a@b.com, c@d.com" }, owned) !== "string") throw new Error("two recipients accepted");
  if (typeof parseSend({ ...ok, to: "a@b.com\r\nBcc: x@y.com" }, owned) !== "string") throw new Error("header injection accepted");
  if (typeof parseSend({ ...ok, body: "  " }, owned) !== "string") throw new Error("empty body accepted");
});

Deno.test("a long non-ASCII subject folds into short lines and reads back whole", () => {
  const subject = "Rückmeldung zur Masterarbeit – Änderungen bitte bis Freitag 🙏 ".repeat(6).trim();
  const raw = new TextDecoder().decode(buildDraft({ from: "a@b.de", to: "c@d.de", subject, body: "x", inReplyTo: "" }));
  const head = raw.split("\r\n\r\n")[0];
  if (head.split("\r\n").some((line) => line.length > 100)) throw new Error("a header line is too long");
  if (parseHeaders(head).subject !== `Re: ${subject}`) throw new Error(parseHeaders(head).subject);
});
