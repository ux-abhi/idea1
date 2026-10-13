// © Pexilim
import type { Transport } from "./imap.ts";
import { dotStuff, Smtp } from "./smtp.ts";

/** A scripted SMTP server: answers each command by its first word; records what the client sent. */
function fakeServer(script: Record<string, string>): { transport: Transport; sent: string[] } {
  const sent: string[] = [];
  const queue: Uint8Array[] = [];
  const enc = new TextEncoder();
  const transport: Transport = {
    read: () => Promise.resolve(queue.shift() ?? null),
    write: (data) => {
      const text = new TextDecoder().decode(data);
      sent.push(text);
      const word = text.startsWith(".\r\n") ? "." : text.match(/^([A-Z]+)/)?.[1];
      if (word && script[word] !== undefined) queue.push(enc.encode(script[word]));
      return Promise.resolve();
    },
    close: () => {},
  };
  return { transport, sent };
}

const happy = {
  AUTH: "235 2.7.0 Accepted\r\n", MAIL: "250 OK\r\n", RCPT: "250 OK\r\n", DATA: "354 Go ahead\r\n", ".": "250 2.0.0 Queued\r\n",
  QUIT: "221 Bye\r\n", EHLO: "250-smtp.example\r\n250-AUTH PLAIN\r\n250 STARTTLS\r\n",
};

Deno.test("deliver logs in, sends one message and quits", async () => {
  const { transport, sent } = fakeServer(happy);
  const smtp = new Smtp(transport);
  await smtp.expect("EHLO blink", [250]); // reads the whole multi-line reply
  await smtp.deliver({ user: "me@icloud.com", password: "pw", from: "hello@example.com", to: "w@tv.com", message: new TextEncoder().encode("Subject: Hi\r\n\r\n.hidden\r\nbye") });
  const all = sent.join("");
  if (!all.includes(`AUTH PLAIN ${btoa("\0me@icloud.com\0pw")}\r\n`) || !all.includes("MAIL FROM:<hello@example.com>\r\n") ||
      !all.includes("RCPT TO:<w@tv.com>\r\n") || !all.includes("\r\n..hidden\r\nbye\r\n") || !all.endsWith("QUIT\r\n")) {
    throw new Error(JSON.stringify(sent));
  }
});

Deno.test("a refused recipient stops the send and the error never shows the password", async () => {
  const { transport } = fakeServer({ ...happy, AUTH: "535 5.7.8 Bad credentials\r\n" });
  try {
    await new Smtp(transport).deliver({ user: "me", password: "secret-pw", from: "a@b.c", to: "d@e.f", message: new Uint8Array() });
    throw new Error("should have failed");
  } catch (error) {
    const text = (error as Error).message;
    if (!text.includes("refused the login") || text.includes("secret") || text.includes(btoa("\0me\0secret-pw"))) throw error;
  }
});

Deno.test("dot stuffing doubles leading dots and normalises line endings", () => {
  const out = new TextDecoder().decode(dotStuff(new TextEncoder().encode(".a\nb\n.")));
  if (out !== "..a\r\nb\r\n..\r\n") throw new Error(JSON.stringify(out));
});
