// © Pexilim
import { buildDraft, parseAddress, parseHeaders, parseTriage, plainText, replyFrom } from "./message.ts";

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
  if (/\r\nBcc:/i.test(raw) || !raw.includes("In-Reply-To: <abc@tv.com>") || !raw.includes("Subject: Re: Interview Bcc") || !raw.includes("\r\n\r\nHi Wolfram,\r\nThanks.")) {
    throw new Error(raw);
  }
  if (replyFrom("Hello <hello@uxabhi.com>", "", "me@icloud.com", ["hello@pexilim.com", "hello@uxabhi.com"]) !== "hello@uxabhi.com") throw new Error("alias");
  if (replyFrom("other@x.com", "", "me@icloud.com", []) !== "me@icloud.com") throw new Error("fallback");
});
