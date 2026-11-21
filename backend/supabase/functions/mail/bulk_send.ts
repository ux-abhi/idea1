// © Pexilim
// Bulk Mail sending (ADR-0003 §3, step 3): a "mail.bulk" red action holds every approved mail of a batch exactly as the
// owner signed it with Touch ID. Each scheduled run sends at most one mail per mailbox, inside daytime hours and the
// daily limits, skips anyone who replied, and pauses the batch on a provider's limit error or repeated failures.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.118.0";
import { checkedFiles } from "./bulk.ts";
import { buildDraft } from "./message.ts";
import { type Mailer, withTimeout } from "./outbox.ts";

export type BulkMail = { id: string; to: string; subject: string; body: string };
export type BulkPayload = { campaign_id: string; account: string; mails: BulkMail[]; files: unknown };

/** Most mails one mailbox sends in 24 hours across all bulk mails: a fifth of Gmail's personal limit, so normal mail
 *  always has room and the account never looks like a sender of bulk mail. */
export const DAILY_CEILING = 100;

const UUID = /^[0-9a-f-]{36}$/i;
const ADDRESS = /^[^@\s,;<>"]+@[^@\s,;<>"]+\.[^@\s,;<>"]+$/;

/** The signed payload, checked: a known mailbox, 1 to 100 mails, each with an id, a real address and some text. */
export function parseBulk(payload: unknown): BulkPayload | string {
  const p = (payload ?? {}) as Record<string, unknown>;
  if (typeof p.campaign_id !== "string" || !UUID.test(p.campaign_id)) return "The bulk mail is missing.";
  if (!["gmail", "icloud", "uni"].includes(String(p.account))) return "Unknown mailbox.";
  if (!Array.isArray(p.mails) || p.mails.length < 1 || p.mails.length > 100) return "A batch holds 1 to 100 mails.";
  const mails: BulkMail[] = [];
  for (const raw of p.mails as Record<string, unknown>[]) {
    const [id, to, subject, body] = [raw?.id, raw?.to, raw?.subject, raw?.body].map((v) => typeof v === "string" ? v : "");
    if (!UUID.test(id) || !ADDRESS.test(to) || to.length > 320) return "A recipient's address doesn't look right.";
    if (!subject.trim() || subject.length > 300 || !body.trim() || body.length > 20000) return "A mail in the batch is empty or too long.";
    mails.push({ id, to, subject, body });
  }
  return { campaign_id: p.campaign_id, account: String(p.account), mails, files: p.files };
}

/** A mail provider saying "too much, slow down" (rate limits, daily quota, temporary blocks). */
export const isLimitError = (message: string) =>
  /\b(421|450|451|452|454)\b|5\.4\.5|5\.7\.0|quota|rate.?limit|too many|try again later|temporarily/i.test(message);

/** Whether `now` is between 8:00 and 20:00 in the owner's time zone (UTC if it's unknown). */
export function inSendingHours(now: Date, zone: unknown): boolean {
  let hour: number;
  try {
    hour = Number(new Intl.DateTimeFormat("en-GB", { hour: "numeric", hourCycle: "h23", timeZone: typeof zone === "string" && zone ? zone : "UTC" }).format(now));
  } catch {
    hour = now.getUTCHours();
  }
  return hour >= 8 && hour < 20;
}

/** Sends what's due from every approved batch: at most one mail per mailbox per run. */
export async function sendBulkDue(admin: SupabaseClient, owner: string, mailer: Mailer, now = Date.now()): Promise<{ sent: number; failed: number }> {
  const at = new Date(now).toISOString();
  // A mail claimed more than 10 minutes ago and never confirmed was cut off mid-way: say so, never send it again.
  await admin.from("mail_recipient").update({ status: "failed", error: "Blink stopped while sending. It may not have gone out; check Sent in your mail app." })
    .eq("owner_id", owner).eq("status", "sent").is("sent_at", null).lt("updated_at", new Date(now - 10 * 60_000).toISOString());

  const { data: profile } = await admin.from("profile").select("timezone").eq("owner_id", owner).maybeSingle();
  if (!inSendingHours(new Date(now), profile?.timezone)) return { sent: 0, failed: 0 };
  const { count: today } = await admin.from("mail_recipient").select("id", { count: "exact", head: true })
    .eq("owner_id", owner).gte("sent_at", new Date(now - 86_400_000).toISOString());
  if ((today ?? 0) >= DAILY_CEILING) return { sent: 0, failed: 0 };

  const { data: actions } = await admin.from("action").select("id, payload, decided_at").eq("owner_id", owner).eq("kind", "mail.bulk")
    .eq("risk", "red").eq("status", "approved").order("created_at").limit(10);
  let sent = 0, failed = 0;
  const used = new Set<string>(); // mailboxes that already sent this run
  for (const action of actions ?? []) {
    const batch = parseBulk(action.payload);
    if (typeof batch === "string") {
      await admin.from("action").update({ status: "failed", result: { error: batch } }).eq("id", action.id);
      continue;
    }
    if (used.has(batch.account)) continue;
    const { data: campaign } = await admin.from("mail_campaign").select("status, daily_limit").eq("id", batch.campaign_id).eq("owner_id", owner).maybeSingle();
    if (!campaign) {
      await admin.from("action").update({ status: "failed", result: { error: "The bulk mail was deleted." } }).eq("id", action.id);
      continue;
    }
    if (campaign.status !== "sending") continue; // paused by the owner or by Blink
    const { count: campaignToday } = await admin.from("mail_recipient").select("id", { count: "exact", head: true })
      .eq("campaign_id", batch.campaign_id).gte("sent_at", new Date(now - 86_400_000).toISOString());
    if ((campaignToday ?? 0) >= Number(campaign.daily_limit ?? 20)) continue;

    const { data: rows } = await admin.from("mail_recipient").select("id, status").eq("owner_id", owner).in("id", batch.mails.map((m) => m.id));
    const status = new Map((rows ?? []).map((r) => [r.id as string, r.status as string]));
    // Someone who wrote back since the batch was approved gets nothing more from it.
    const { data: replies } = await admin.from("email_msg").select("from_addr").eq("owner_id", owner).gte("received_at", action.decided_at ?? at).limit(1000);
    const repliedFrom = new Set((replies ?? []).map((r) => String(r.from_addr).toLowerCase()));
    for (const mail of batch.mails) {
      if (status.get(mail.id) === "approved" && repliedFrom.has(mail.to.toLowerCase())) {
        await admin.from("mail_recipient").update({ status: "replied" }).eq("id", mail.id).eq("status", "approved");
        status.set(mail.id, "replied");
      }
    }
    // Only mails still approved: the owner can take one out (Skip) at any time; a deleted contact is never mailed.
    const next = batch.mails.find((m) => status.get(m.id) === "approved");
    if (!next) { // nothing left to send: the batch is finished
      await admin.from("mail_campaign").update({ status: "done" }).eq("id", batch.campaign_id).eq("status", "sending");
      await admin.from("action").update({ status: "done", result: { finished_at: at } }).eq("id", action.id).eq("status", "approved");
      continue;
    }
    const { data: claimed } = await admin.from("mail_recipient").update({ status: "sent", sent_at: null, error: null })
      .eq("id", next.id).eq("status", "approved").select("id");
    if (!claimed?.length) continue;
    used.add(batch.account);
    try {
      const owned = mailer.owned(batch.account);
      if (!owned) throw new Error("That mailbox isn't connected anymore.");
      const list = checkedFiles(batch.files, owner);
      if (typeof list === "string") throw new Error(list);
      const files = await Promise.all(list.map(async (f) => {
        const { data, error } = await admin.storage.from("files").download(f.path);
        if (error || !data) throw new Error(`Couldn't read the attachment “${f.name}”.`);
        return { name: f.name, type: f.type, data: new Uint8Array(await data.arrayBuffer()) };
      }));
      const from = owned[0];
      const messageId = `<${crypto.randomUUID()}@${from.split("@")[1] || "blink.local"}>`;
      const message = buildDraft({ from, to: next.to, subject: next.subject, body: next.body, inReplyTo: "", messageId, fresh: true, attachments: files });
      await withTimeout(mailer.send(batch.account, from, next.to, message), 60_000, "The mail server didn't answer in time. It may not have been sent.");
      sent++;
      await admin.from("mail_recipient").update({ sent_at: new Date().toISOString(), message_id: messageId }).eq("id", next.id);
      await mailer.tidy(batch.account, message, messageId).catch((e) => console.error("after bulk send", e?.message ?? e));
    } catch (error) {
      failed++;
      const text = error instanceof Error ? error.message.slice(0, 300) : "Couldn't send.";
      await admin.from("mail_recipient").update({ status: "failed", error: text }).eq("id", next.id);
      // A provider asking to slow down, or three failures in a row: stop the whole batch until the owner resumes it.
      const { data: last } = await admin.from("mail_recipient").select("status").eq("campaign_id", batch.campaign_id)
        .in("status", ["sent", "failed"]).order("updated_at", { ascending: false }).limit(3);
      const streak = (last ?? []).length === 3 && (last ?? []).every((r) => r.status === "failed");
      if (isLimitError(text) || streak) await admin.from("mail_campaign").update({ status: "paused" }).eq("id", batch.campaign_id);
    }
  }
  return { sent, failed };
}
