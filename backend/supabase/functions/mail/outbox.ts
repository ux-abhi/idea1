// © Pexilim
// Sending approved mail (ARCHITECTURE §36.5): only red "mail.send" actions, approved by a verified Touch ID signature over
// this exact payload, are sent, each exactly once, at its time. Kept apart from the server so it can be tested.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.49.4";
import { buildDraft, parseSend } from "./message.ts";

/** What sending needs from the mail worker: the connected mailbox, SMTP, and the after-send tidy-up. */
export type Mailer = {
  /** The owner's own addresses for a connected account id, or null when it isn't connected. */
  owned(account: string): string[] | null;
  send(account: string, from: string, to: string, message: Uint8Array): Promise<void>;
  /** A copy in Sent and Blink's draft out of Drafts; the mail is already sent, so a failure here is only logged. */
  tidy(account: string, message: Uint8Array, messageId: string): Promise<void>;
};

/** Rejects if `work` takes longer than `ms`, so one stalled server can't use up the whole run. */
export function withTimeout<T>(work: Promise<T>, ms: number, message: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return Promise.race([work, new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error(message)), ms); })])
    .finally(() => clearTimeout(timer));
}

/** Sends every approved "mail.send" whose time has come. Each is claimed first (approved → done, conditional), so the
 *  schedule and the app can't both send it. */
export async function sendDue(admin: SupabaseClient, owner: string, mailer: Mailer, now = Date.now()): Promise<{ sent: number; failed: number }> {
  // A send claimed more than 10 minutes ago and never confirmed was cut off mid-way (the run was killed): say so.
  await admin.from("action").update({ status: "failed", result: { error: "Blink stopped while sending. It may not have gone out; check Sent in Apple Mail." } })
    .eq("owner_id", owner).eq("kind", "mail.send").eq("status", "done").is("result->>sent_at", null)
    .lt("result->>sending_at", new Date(now - 10 * 60_000).toISOString());

  // Due now (2 s of slack for the device's clock), soonest first, so mail scheduled for later never blocks it.
  const { data: due } = await admin.from("action").select("id, payload").eq("owner_id", owner).eq("kind", "mail.send")
    .eq("risk", "red").eq("status", "approved").lte("payload->>send_at", new Date(now + 2000).toISOString())
    .order("payload->>send_at").limit(10);
  let sent = 0, failed = 0;
  for (const action of due ?? []) {
    const { data: claimed } = await admin.from("action").update({ status: "done", result: { sending_at: new Date().toISOString() } })
      .eq("id", action.id).eq("status", "approved").select("id");
    if (!claimed?.length) continue;
    try {
      const owned = mailer.owned(String(action.payload?.account ?? ""));
      if (!owned) throw new Error("That mailbox isn't connected anymore.");
      const mail = parseSend(action.payload, owned);
      if (typeof mail === "string") throw new Error(mail);
      const message = buildDraft({ from: mail.from, to: mail.to, subject: mail.subject, body: mail.body, inReplyTo: mail.in_reply_to, messageId: mail.message_id });
      // A stalled mail server fails the send (and says so) instead of leaving it looking sent.
      await withTimeout(mailer.send(mail.account, mail.from, mail.to, message), 60_000,
        "The mail server didn't answer in time. It may not have been sent; check Sent in Apple Mail.");
      sent++;
      await admin.from("action").update({ result: { sent_at: new Date().toISOString() } }).eq("id", action.id);
      await admin.from("email_msg").update({ status: "done" }).eq("id", mail.email_id).eq("owner_id", owner);
      await mailer.tidy(mail.account, message, mail.message_id).catch((e) => console.error("after send", e?.message ?? e));
    } catch (error) {
      failed++;
      await admin.from("action").update({ status: "failed", result: { error: error instanceof Error ? error.message.slice(0, 300) : "Couldn't send." } })
        .eq("id", action.id);
    }
  }
  return { sent, failed };
}
