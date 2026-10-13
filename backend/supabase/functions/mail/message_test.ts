// © Pexilim
import { parseSpend, splitResort, buildDraft, parseAddress, parseHeaders, parseTriage, plainText, replyFrom, ruleVerdict, parseSend, settle, uidWindow } from "./message.ts";

Deno.test("headers unfold and decode encoded words", () => {
  const h = parseHeaders("Subject: =?UTF-8?B?SW50ZXJ2aWV3IOKAkyBBY21l?=\r\nFrom: \"Wolfram\"\r\n <w@acme.example>\r\nTo: hello@example.com\r\n");
  if (h.subject !== "Interview – Acme" || parseAddress(h.from).address !== "w@acme.example" || parseAddress(h.from).name !== "Wolfram") {
    throw new Error(JSON.stringify(h));
  }
  if (parseAddress("ada@example.com").address !== "ada@example.com") throw new Error("bare address");
});

Deno.test("plain text comes from the text part of multipart mail, decoded, without HTML", () => {
  const boundary = "XYZ";
  const body = `--XYZ\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nHallo Sam,=0Asee you Monday=21\r\n--XYZ\r\nContent-Type: text/html\r\n\r\n<p>ignored</p>\r\n--XYZ--`;
  const text = plainText(body, { "content-type": `multipart/alternative; boundary="${boundary}"` });
  if (text !== "Hallo Sam,\nsee you Monday!") throw new Error(JSON.stringify(text));
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
    from: "hello@example.com", to: "w@acme.example\r\nBcc: evil@x.com", subject: "Interview\nBcc: evil@x.com",
    body: "Hi Wolfram,\nThanks.", inReplyTo: "<abc@tv.com>", date: new Date("2026-10-12T10:00:00Z"),
  }));
  const body = atob(raw.split("\r\n\r\n")[1].replaceAll("\r\n", ""));
  if (/\r\nBcc:/i.test(raw) || !raw.includes("In-Reply-To: <abc@tv.com>") || !raw.includes("Subject: Re: Interview Bcc") || body !== "Hi Wolfram,\r\nThanks.") {
    throw new Error(raw);
  }
  if (replyFrom("Hello <hi@example.org>", "", "me@icloud.com", ["hello@example.com", "hi@example.org"]) !== "hi@example.org") throw new Error("alias");
  if (replyFrom("other@x.com", "", "me@icloud.com", []) !== "me@icloud.com") throw new Error("fallback");
});

Deno.test("job alerts and no-reply senders are settled in code", () => {
  const hot = { triage: "important" as const, reason: "Job posting", needs_reply: true };
  if (settle(hot, "noreply@glassdoor.com").triage !== "newsletter") throw new Error("glassdoor");
  if (settle(hot, "info@jobagent.stepstone.de").triage !== "newsletter") throw new Error("stepstone");
  if (settle(hot, "jobalerts-noreply@linkedin.com").triage !== "newsletter") throw new Error("linkedin");
  if (settle(hot, "recruiter@acme.example").triage !== "important") throw new Error("a real recruiter stays important");
  if (settle(hot, "no-reply@accounts.google.com").needs_reply) throw new Error("no-reply can't need a reply");
  if (!settle(hot, "sam@example.com").needs_reply) throw new Error("people keep needs_reply");
});

Deno.test("the owner's sender rules: exact address first, then the domain and its subdomains", () => {
  const rules = [{ sender: "@glassdoor.com", verdict: "newsletter" as const }, { sender: "boss@glassdoor.com", verdict: "important" as const }];
  if (ruleVerdict(rules, "Boss@glassdoor.com") !== "important") throw new Error("exact");
  if (ruleVerdict(rules, "noreply@mail.glassdoor.com") !== "newsletter") throw new Error("subdomain");
  if (ruleVerdict(rules, "x@notglassdoor.com") !== null) throw new Error("lookalike domain matched");
});

Deno.test("a send is checked before it leaves", () => {
  const ok = { email_id: "e1", account: "icloud", from: "hello@example.com", to: "w@tv.com", subject: "Re: Hi", body: "Thanks",
    in_reply_to: "<a@tv.com>", message_id: "<b@pexilim.com>", send_at: "2026-10-15T07:00:00Z" };
  const owned = ["me@icloud.com", "hello@example.com"];
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

Deno.test("a burst of new mail is read oldest first across checks, none skipped", () => {
  const found = Array.from({ length: 20 }, (_, i) => 101 + i); // UIDs 101–120 arrived since last = 100
  const first = uidWindow(found, 100, 121);
  if (first.take[0] !== 101 || first.take.length !== 15 || first.last !== 115) throw new Error(JSON.stringify(first));
  const second = uidWindow(found.filter((u) => u > first.last), first.last, 121);
  if (second.take.join() !== "116,117,118,119,120" || second.last !== 120) throw new Error(JSON.stringify(second));
  const fresh = uidWindow(found, null, 121);
  if (fresh.take[0] !== 106 || fresh.last !== 120) throw new Error(JSON.stringify(fresh));
  if (uidWindow([], 100, 130).last !== 129) throw new Error("an empty check should move to uidNext - 1");
});

Deno.test("the reply comes from the whole address the mail went to, never a lookalike", () => {
  if (replyFrom("dab@x.com", "", "me@icloud.com", ["ab@x.com"]) !== "me@icloud.com") throw new Error("lookalike matched");
  if (replyFrom("Other <o@y.com>", "AB <AB@x.com>", "me@icloud.com", ["ab@x.com"]) !== "ab@x.com") throw new Error("cc not matched");
});

Deno.test("receipts become spends only when they're clear euro payments", () => {
  const ok = parseSpend({ spend_amount: 12.989, spend_currency: "eur", spend_merchant: "  Amazon ", spend_category: "shopping" });
  if (ok?.amount !== 12.99 || ok.merchant !== "Amazon" || ok.category !== "shopping") throw new Error(JSON.stringify(ok));
  if (parseSpend({ spend_amount: 0, spend_currency: "EUR" }) || parseSpend({ spend_amount: 5, spend_currency: "USD" }) ||
      parseSpend({ spend_amount: -5, spend_currency: "EUR" }) || parseSpend({ spend_amount: "x", spend_currency: "EUR" })) {
    throw new Error("a non-spend was accepted");
  }
  if (parseSpend({ spend_amount: 3, spend_currency: "EUR", spend_category: "crypto" })?.category !== "other") throw new Error("category");
});

Deno.test("unsorted mail is sorted again on a later check, never inserted twice", () => {
  const rows = [{ uid: 1, sorted: true }, { uid: 2, sorted: true }, { uid: 3, sorted: false }, { uid: 9, sorted: false }];
  const { fresh, sortedAgain } = splitResort(rows, [1, 3]);
  if (JSON.stringify(fresh.map((r) => r.uid)) !== "[2,9]") throw new Error(`fresh ${JSON.stringify(fresh)}`);
  if (JSON.stringify(sortedAgain.map((r) => r.uid)) !== "[1]") throw new Error(`again ${JSON.stringify(sortedAgain)}`);
});
