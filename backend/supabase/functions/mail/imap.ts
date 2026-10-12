// © Pexilim
// A small IMAP client (RFC 3501) for the mail worker: log in, find Drafts, read new message headers and a text snippet,
// fetch one message's text on demand, and append a draft. Only what Blink needs; tested against recorded replies.

export interface Transport {
  read(): Promise<Uint8Array | null>;
  write(data: Uint8Array): Promise<void>;
  close(): void;
}

/** One untagged response: its text (literals replaced by {n}) and its literals, each keyed by the item that preceded it. */
export type Response = { text: string; literals: { key: string; data: Uint8Array }[] };

const enc = new TextEncoder();
const dec = new TextDecoder();

export class ImapError extends Error {}

/** CRLF lines and fixed-size byte runs from a transport; shared by the IMAP and SMTP clients. */
export class LineReader {
  private buffer = new Uint8Array(0);

  constructor(private transport: Transport, private maxLine = 1_000_000) {}

  private async fill(): Promise<void> {
    const chunk = await this.transport.read();
    if (!chunk) throw new Error("The mail server closed the connection.");
    const next = new Uint8Array(this.buffer.length + chunk.length);
    next.set(this.buffer);
    next.set(chunk, this.buffer.length);
    this.buffer = next;
  }

  async readLine(): Promise<string> {
    for (;;) {
      const at = this.buffer.findIndex((b, i) => b === 13 && this.buffer[i + 1] === 10);
      if (at >= 0) {
        const line = dec.decode(this.buffer.subarray(0, at));
        this.buffer = this.buffer.subarray(at + 2);
        return line;
      }
      if (this.buffer.length > this.maxLine) throw new Error("A line from the mail server was too long.");
      await this.fill();
    }
  }

  async readBytes(n: number): Promise<Uint8Array> {
    if (n > 5_000_000) throw new Error("A message part was too large.");
    while (this.buffer.length < n) await this.fill();
    const data = this.buffer.slice(0, n);
    this.buffer = this.buffer.subarray(n);
    return data;
  }
}

export class Imap {
  private lines: LineReader;
  private counter = 0;

  constructor(private transport: Transport) {
    this.lines = new LineReader(transport);
  }

  /** TLS to port 993, then the server's greeting. */
  static async connect(hostname: string): Promise<Imap> {
    const conn = await Deno.connectTls({ hostname, port: 993 });
    const imap = new Imap({
      read: async () => {
        const chunk = new Uint8Array(32768);
        const n = await conn.read(chunk);
        return n === null ? null : chunk.subarray(0, n);
      },
      write: async (data) => {
        let sent = 0;
        while (sent < data.length) sent += await conn.write(data.subarray(sent));
      },
      close: () => { try { conn.close(); } catch { /* already closed */ } },
    });
    const greeting = await imap.readLine();
    if (!greeting.startsWith("* OK")) throw new ImapError("The mail server didn't say hello.");
    return imap;
  }

  readLine(): Promise<string> {
    return this.lines.readLine();
  }

  /** Reads one logical response: a line, plus any literals ({n}) and the lines that continue it. */
  private async readResponse(): Promise<Response> {
    let text = "";
    const literals: Response["literals"] = [];
    for (;;) {
      const line = await this.readLine();
      const literal = line.match(/\{(\d+)\}$/);
      if (!literal) return { text: text + line, literals };
      const before = line.slice(0, literal.index);
      text += line;
      // The item the literal belongs to, e.g. "BODY[TEXT]<0>" or "BODY[HEADER.FIELDS (FROM TO)]".
      const key = before.match(/(BODY\[[^\]]*\](?:<\d+>)?)\s*$/)?.[1] ?? "";
      literals.push({ key, data: await this.lines.readBytes(Number(literal[1])) });
    }
  }

  /** Sends a command; returns the untagged responses, or throws with the server's words if it says NO or BAD. */
  async command(cmd: string, literal?: Uint8Array): Promise<Response[]> {
    const tag = `B${++this.counter}`;
    const responses: Response[] = [];
    if (literal) {
      await this.transport.write(enc.encode(`${tag} ${cmd} {${literal.length}}\r\n`));
      const go = await this.readLine();
      if (!go.startsWith("+")) throw new ImapError(go.replace(/^\S+\s+/, "").slice(0, 200));
      await this.transport.write(literal);
      await this.transport.write(enc.encode("\r\n"));
    } else {
      await this.transport.write(enc.encode(`${tag} ${cmd}\r\n`));
    }
    for (;;) {
      const response = await this.readResponse();
      if (response.text.startsWith(`${tag} `)) {
        const status = response.text.slice(tag.length + 1);
        if (!status.startsWith("OK")) throw new ImapError(status.replace(/^(NO|BAD)\s*/, "").slice(0, 200));
        return responses;
      }
      if (!response.text.startsWith("+")) responses.push(response);
    }
  }

  login(user: string, password: string) {
    return this.command(`LOGIN ${quote(user)} ${quote(password)}`);
  }

  /** Opens a mailbox; returns its UIDVALIDITY and UIDNEXT. */
  async select(mailbox: string, readOnly = true): Promise<{ uidValidity: number; uidNext: number }> {
    const responses = await this.command(`${readOnly ? "EXAMINE" : "SELECT"} ${quote(mailbox)}`);
    const find = (name: string) => Number(responses.map((r) => r.text.match(new RegExp(`${name} (\\d+)`))?.[1]).find(Boolean) ?? 0);
    return { uidValidity: find("UIDVALIDITY"), uidNext: find("UIDNEXT") };
  }

  /** The mailbox marked with a special-use flag (\\Drafts, \\Sent), or `fallback` if the server marks none. */
  async specialMailbox(flag: "\\Drafts" | "\\Sent", fallback: string): Promise<string> {
    const responses = await this.command(`LIST "" "*"`);
    for (const r of responses) {
      const m = r.text.match(/^\* LIST \(([^)]*)\) (?:"[^"]*"|NIL) (.+)$/);
      if (m && m[1].toLowerCase().split(/\s+/).includes(flag.toLowerCase())) return unquote(m[2]);
    }
    return fallback;
  }

  draftsMailbox() {
    return this.specialMailbox("\\Drafts", "Drafts");
  }

  /** Removes the messages with this Message-ID from a mailbox (Blink's own draft, once it's sent). */
  async deleteByMessageId(mailbox: string, messageId: string): Promise<number> {
    await this.select(mailbox, false);
    const uids = await this.uidSearch(`HEADER Message-ID ${quote(messageId)}`);
    if (uids.length === 0) return 0;
    await this.command(`UID STORE ${uids.join(",")} +FLAGS.SILENT (\\Deleted)`);
    await this.command("EXPUNGE");
    return uids.length;
  }

  async uidSearch(criteria: string): Promise<number[]> {
    const responses = await this.command(`UID SEARCH ${criteria}`);
    return responses.flatMap((r) => r.text.startsWith("* SEARCH") ? r.text.slice(8).trim().split(/\s+/).filter(Boolean).map(Number) : []);
  }

  /** Headers (and optionally the first `snippet` bytes of the text) for the given UIDs. */
  async fetch(uids: number[], snippet: number): Promise<{ uid: number; date: string | null; header: string; text: string }[]> {
    if (uids.length === 0) return [];
    const fields = "FROM TO CC REPLY-TO SUBJECT DATE MESSAGE-ID IN-REPLY-TO LIST-UNSUBSCRIBE CONTENT-TYPE CONTENT-TRANSFER-ENCODING";
    const parts = `UID INTERNALDATE BODY.PEEK[HEADER.FIELDS (${fields})]${snippet ? ` BODY.PEEK[TEXT]<0.${snippet}>` : ""}`;
    const responses = await this.command(`UID FETCH ${uids.join(",")} (${parts})`);
    return responses.filter((r) => /^\* \d+ FETCH/.test(r.text)).map((r) => ({
      uid: Number(r.text.match(/UID (\d+)/)?.[1] ?? 0),
      date: r.text.match(/INTERNALDATE "([^"]+)"/)?.[1] ?? null,
      header: dec.decode(r.literals.find((l) => l.key.startsWith("BODY[HEADER"))?.data ?? new Uint8Array()),
      text: dec.decode(r.literals.find((l) => l.key.startsWith("BODY[TEXT]"))?.data ?? new Uint8Array()),
    })).filter((m) => m.uid > 0);
  }

  /** Saves a finished message (RFC 5322 bytes) into a mailbox, flagged as a draft (or only as read, for Sent). */
  append(mailbox: string, message: Uint8Array, flags = "(\\Draft \\Seen)") {
    return this.command(`APPEND ${quote(mailbox)} ${flags}`, message);
  }

  async logout() {
    try { await this.command("LOGOUT"); } catch { /* closing anyway */ }
    this.transport.close();
  }
}

export function quote(s: string): string {
  return `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

function unquote(s: string): string {
  const t = s.trim();
  return t.startsWith('"') ? t.slice(1, -1).replace(/\\(["\\])/g, "$1") : t;
}
