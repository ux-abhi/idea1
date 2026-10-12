// © Pexilim
// A small SMTP client (RFC 5321) for sending one approved message: TLS (465) or STARTTLS (587), AUTH PLAIN, one
// recipient. Only what Blink needs; tested against a scripted server.
import { LineReader, type Transport } from "./imap.ts";

export class SmtpError extends Error {}

const enc = new TextEncoder();
const dec = new TextDecoder(); // for dot-stuffing

export class Smtp {
  private lines: LineReader;

  constructor(private transport: Transport) {
    this.lines = new LineReader(transport, 100_000);
  }

  /** Sends a command (or nothing, for the greeting) and checks the reply code; multi-line replies ("250-") are read whole. */
  async expect(command: string | null, ok: number[]): Promise<void> {
    if (command !== null) await this.transport.write(enc.encode(`${command}\r\n`));
    let line: string;
    do { line = await this.lines.readLine(); } while (line[3] === "-");
    const code = Number(line.slice(0, 3));
    if (!ok.includes(code)) {
      // Never echo the AUTH line: it carries the password.
      const what = command?.startsWith("AUTH") ? "login" : command?.split(" ")[0] ?? "greeting";
      throw new SmtpError(`The mail server refused the ${what}: ${line.slice(0, 200)}`);
    }
  }

  /** Everything after the greeting and EHLO: log in, hand over one message, quit. */
  async deliver(p: { user: string; password: string; from: string; to: string; message: Uint8Array }): Promise<void> {
    const plain = btoa(String.fromCharCode(...enc.encode(`\0${p.user}\0${p.password}`)));
    await this.expect(`AUTH PLAIN ${plain}`, [235]);
    await this.expect(`MAIL FROM:<${p.from}>`, [250]);
    await this.expect(`RCPT TO:<${p.to}>`, [250, 251]);
    await this.expect("DATA", [354]);
    await this.transport.write(dotStuff(p.message));
    await this.expect(".", [250]);
    await this.expect("QUIT", [221]).catch(() => {}); // sent already; a rude goodbye doesn't matter
    this.transport.close();
  }
}

/** CRLF line endings, a leading "." doubled (RFC 5321 §4.5.2), ending in CRLF so the "." terminator is on its own line. */
export function dotStuff(message: Uint8Array): Uint8Array {
  const text = dec.decode(message).replace(/\r?\n/g, "\r\n").replace(/^\./gm, "..");
  return enc.encode(text.endsWith("\r\n") ? text : `${text}\r\n`);
}

function wrap(conn: Deno.Conn): Transport {
  return {
    read: async () => {
      const chunk = new Uint8Array(16384);
      const n = await conn.read(chunk);
      return n === null ? null : chunk.subarray(0, n);
    },
    write: async (data) => {
      let sent = 0;
      while (sent < data.length) sent += await conn.write(data.subarray(sent));
    },
    close: () => { try { conn.close(); } catch { /* already closed */ } },
  };
}

/** Sends one message: implicit TLS on 465, STARTTLS on any other port. */
export async function sendMail(host: string, port: number, p: Parameters<Smtp["deliver"]>[0]): Promise<void> {
  if (port === 465) {
    const smtp = new Smtp(wrap(await Deno.connectTls({ hostname: host, port })));
    await smtp.expect(null, [220]);
    await smtp.expect("EHLO blink", [250]);
    return smtp.deliver(p);
  }
  const tcp = await Deno.connect({ hostname: host, port });
  const plain = new Smtp(wrap(tcp));
  await plain.expect(null, [220]);
  await plain.expect("EHLO blink", [250]);
  await plain.expect("STARTTLS", [220]);
  const smtp = new Smtp(wrap(await Deno.startTls(tcp, { hostname: host })));
  await smtp.expect("EHLO blink", [250]);
  return smtp.deliver(p);
}
