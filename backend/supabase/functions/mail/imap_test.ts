// © Pexilim
import { Imap, Transport } from "./imap.ts";

/** A fake server: replies to each tagged command with canned lines; records what the client sent. */
function fakeServer(script: Record<string, string>): { transport: Transport; sent: string[] } {
  const sent: string[] = [];
  const queue: Uint8Array[] = [];
  const enc = new TextEncoder();
  const transport: Transport = {
    read: () => Promise.resolve(queue.shift() ?? null),
    write: (data) => {
      const text = new TextDecoder().decode(data);
      sent.push(text);
      const m = text.match(/^(B\d+) (\S+)/);
      if (m) {
        const reply = script[m[2]];
        if (reply !== undefined) queue.push(enc.encode(reply.replaceAll("TAG", m[1])));
      }
      return Promise.resolve();
    },
    close: () => {},
  };
  return { transport, sent };
}

Deno.test("fetch reads headers and text literals for each message", async () => {
  const header = "From: =?UTF-8?B?VGVhbVZpZXdlcg==?= <jobs@teamviewer.com>\r\nSubject: Interview\r\n\r\n";
  const body = "Hello Abhishek";
  const { transport, sent } = fakeServer({
    UID: `* 1 FETCH (UID 42 INTERNALDATE "12-Oct-2026 10:00:00 +0000" BODY[HEADER.FIELDS (FROM TO)] {${header.length}}\r\n${header}` +
      ` BODY[TEXT]<0> {${body.length}}\r\n${body})\r\nTAG OK done\r\n`,
  });
  const imap = new Imap(transport);
  const messages = await imap.fetch([42], 2000);
  if (!sent[0].includes("UID FETCH 42 (UID INTERNALDATE BODY.PEEK[HEADER.FIELDS")) throw new Error(sent[0]);
  if (messages.length !== 1 || messages[0].uid !== 42 || !messages[0].header.includes("jobs@teamviewer.com") || messages[0].text !== body) {
    throw new Error(JSON.stringify(messages));
  }
});

Deno.test("drafts mailbox comes from the special-use flag, select reads UIDVALIDITY, errors carry the server's words", async () => {
  const { transport } = fakeServer({
    LIST: `* LIST (\\HasNoChildren) "/" "INBOX"\r\n* LIST (\\HasNoChildren \\Drafts) "/" "[Gmail]/Drafts"\r\nTAG OK\r\n`,
    EXAMINE: `* 3 EXISTS\r\n* OK [UIDVALIDITY 1234] ok\r\n* OK [UIDNEXT 99] ok\r\nTAG OK [READ-ONLY]\r\n`,
    LOGIN: `TAG NO [AUTHENTICATIONFAILED] Invalid credentials\r\n`,
  });
  const imap = new Imap(transport);
  if (await imap.draftsMailbox() !== "[Gmail]/Drafts") throw new Error("drafts");
  const box = await imap.select("INBOX");
  if (box.uidValidity !== 1234 || box.uidNext !== 99) throw new Error(JSON.stringify(box));
  try {
    await imap.login("a@b.c", 'pa"ss');
    throw new Error("login should fail");
  } catch (e) {
    if (!(e instanceof Error) || !e.message.includes("Invalid credentials")) throw e;
  }
});

Deno.test("append waits for the go-ahead before sending the message", async () => {
  const { transport, sent } = fakeServer({ APPEND: "+ Ready\r\nTAG OK [APPENDUID 1 7] done\r\n" });
  const imap = new Imap(transport);
  await imap.append("Drafts", new TextEncoder().encode("Subject: hi\r\n\r\nbody"));
  if (!sent[0].startsWith('B1 APPEND "Drafts" (\\Draft \\Seen) {') || !sent[1].includes("Subject: hi")) throw new Error(JSON.stringify(sent));
});

Deno.test("a sent draft is found by its Message-ID, flagged deleted and expunged", async () => {
  const { transport, sent } = fakeServer({
    SELECT: "* OK [UIDVALIDITY 7] ok\r\nTAG OK [READ-WRITE] done\r\n",
    UID: "* SEARCH 31\r\nTAG OK done\r\n",
    EXPUNGE: "* 3 EXPUNGE\r\nTAG OK done\r\n",
  });
  // UID STORE shares the "UID" word with UID SEARCH: the script answers both with the same SEARCH line, which STORE ignores.
  const removed = await new Imap(transport).deleteByMessageId("Drafts", "<abc@pexilim.com>");
  const all = sent.join("");
  if (removed !== 1 || !all.includes('SELECT "Drafts"') || !all.includes('UID SEARCH HEADER Message-ID "<abc@pexilim.com>"') ||
      !all.includes("UID STORE 31 +FLAGS.SILENT (\\Deleted)") || !all.includes("EXPUNGE")) {
    throw new Error(JSON.stringify(sent));
  }
});
