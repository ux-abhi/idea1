// © Pexilim
// Approves a red action only with a fresh signature from the owner's enrolled Secure Enclave key (ARCHITECTURE §36.5).
// The device signs approvalMessage() (verify.ts) after Touch ID / Face ID.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { MAX_TTL_SECONDS, verifyApproval } from "./verify.ts";

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user) return json(401, { error: "signed out" });

  // Trust boundary: check every field before use.
  const body = await req.json().catch(() => null);
  const { action_id, device_id, expires, signature } = body ?? {};
  if (typeof action_id !== "string" || typeof device_id !== "string" || !Number.isInteger(expires) ||
      typeof signature !== "string") {
    return json(400, { error: "action_id, device_id, expires and signature are required" });
  }
  const now = Math.floor(Date.now() / 1000);
  if (expires <= now || expires > now + MAX_TTL_SECONDS) return json(403, { error: "approval expired" });

  const { data: action } = await admin.from("action")
    .select("id, risk, status, payload_hash, expires_at")
    .eq("id", action_id).eq("owner_id", user.id).maybeSingle();
  if (!action || action.risk !== "red" || action.status !== "pending") return json(409, { error: "not a pending red action" });
  if (action.expires_at && Date.parse(action.expires_at) <= Date.now()) return json(409, { error: "action expired" });

  const { data: device } = await admin.from("device")
    .select("id, approval_key, revoked_at")
    .eq("id", device_id).eq("owner_id", user.id).maybeSingle();
  if (!device || device.revoked_at || !device.approval_key) return json(403, { error: "device can't approve" });

  const valid = await verifyApproval(device.approval_key, action.id, action.payload_hash, expires, signature);
  if (!valid) return json(403, { error: "signature doesn't match" });

  // Conditional on still pending, so a replayed signature can't approve twice.
  const { data: updated } = await admin.from("action")
    .update({ status: "approved", decided_at: new Date().toISOString(), decided_by_device: device.id })
    .eq("id", action.id).eq("status", "pending").select("id");
  if (!updated?.length) return json(409, { error: "not a pending red action" });
  return json(200, { status: "approved" });
});
