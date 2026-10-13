// © Pexilim
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.49.4";
import { type Mailer, sendDue } from "./outbox.ts";

type Row = { id: string; status: string; payload: Record<string, unknown>; result?: Record<string, unknown> };

/** Just enough of the Supabase query builder for sendDue, over an in-memory `action` table. */
function fakeAdmin(rows: Row[]) {
  const query = (table: string) => {
    const filters: ((r: Row) => boolean)[] = [];
    let change: Record<string, unknown> | null = null;
    const field = (r: Row, key: string) => key.startsWith("payload->>") ? r.payload[key.slice(10)]
      : key.startsWith("result->>") ? r.result?.[key.slice(9)] : (r as Record<string, unknown>)[key];
    const builder = {
      select: () => builder, order: () => builder, limit: () => builder,
      update: (c: Record<string, unknown>) => { change = c; return builder; },
      eq: (k: string, v: unknown) => { if (!["owner_id", "kind", "risk"].includes(k)) filters.push((r) => field(r, k) === v); return builder; },
      lte: (k: string, v: string) => { filters.push((r) => String(field(r, k)) <= v); return builder; },
      lt: (k: string, v: string) => { filters.push((r) => field(r, k) !== undefined && String(field(r, k)) < v); return builder; },
      is: (k: string, v: null) => { filters.push((r) => (field(r, k) ?? null) === v); return builder; },
      then: (done: (x: { data: unknown }) => void) => {
        if (table !== "action") return done({ data: null });
        const hit = rows.filter((r) => filters.every((f) => f(r)));
        if (change) for (const r of hit) Object.assign(r, change);
        done({ data: hit.map((r) => ({ id: r.id, payload: r.payload })) });
      },
    };
    return builder;
  };
  return { from: query } as unknown as SupabaseClient;
}

const payload = (sendAt: string) => ({ email_id: "e1", account: "icloud", from: "hello@example.com", to: "w@tv.com", subject: "Re: Hi",
  body: "Thanks", in_reply_to: "<a@tv.com>", message_id: "<b@pexilim.com>", send_at: sendAt });

function mailer(sent: string[]): Mailer {
  return { owned: () => ["me@icloud.com", "hello@example.com"], send: (_a, _f, to) => { sent.push(to); return Promise.resolve(); }, tidy: () => Promise.resolve() };
}

Deno.test("two runs at once send an approved mail exactly once, and a later one waits", async () => {
  const now = Date.parse("2026-10-15T07:00:00Z");
  const rows: Row[] = [{ id: "a1", status: "approved", payload: payload("2026-10-15T06:59:00.000Z") },
                       { id: "a2", status: "approved", payload: payload("2026-10-16T07:00:00.000Z") }];
  const sent: string[] = [];
  const admin = fakeAdmin(rows);
  const [one, two] = await Promise.all([sendDue(admin, "o", mailer(sent), now), sendDue(admin, "o", mailer(sent), now)]);
  if (sent.length !== 1 || one.sent + two.sent !== 1) throw new Error(`sent ${sent.length} times`);
  if (rows[0].status !== "done" || rows[1].status !== "approved") throw new Error(JSON.stringify(rows));
});

Deno.test("a send cut off mid-way is marked failed, never resent", async () => {
  const now = Date.parse("2026-10-15T07:30:00Z");
  const rows: Row[] = [{ id: "a1", status: "done", payload: payload("2026-10-15T07:00:00.000Z"), result: { sending_at: "2026-10-15T07:00:05.000Z" } }];
  const sent: string[] = [];
  await sendDue(fakeAdmin(rows), "o", mailer(sent), now);
  if (rows[0].status !== "failed" || sent.length !== 0) throw new Error(JSON.stringify(rows));
});
