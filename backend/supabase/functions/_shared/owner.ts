// © Pexilim
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.49.4";

/** True when this login is the server's one and only owner (the same rule as is_server_owner() in SQL). Functions that
 *  act on server-wide things (the mailboxes, Google) check it, so a second account, if sign-ups were ever turned on,
 *  can't read the owner's mail or use their Google link. */
export async function isServerOwner(admin: SupabaseClient, userId: string): Promise<boolean> {
  const { data, error } = await admin.from("profile").select("owner_id").limit(2);
  return !error && data?.length === 1 && data[0].owner_id === userId;
}
