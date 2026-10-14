// © Pexilim
// Keys and mail passwords: the ones added in the app (Settings › Connections, kept in Vault) win; Edge Function secrets
// are the fallback, so servers set up the old way keep working. The server has one owner, so keys are server-wide.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

let cache: { at: number; keys: Promise<Record<string, string>> } | null = null;

async function load(): Promise<Record<string, string>> {
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data, error } = await admin.rpc("server_keys");
  if (error) {
    console.error("couldn't read saved keys", error.message);
    cache = null; // try again on the next call instead of serving "no keys" for 15 s
    return {};
  }
  return Object.fromEntries((data as { name: string; value: string }[]).map((k) => [k.name, k.value]));
}

/** A key by its secret name. Cached for 15 seconds per instance, so a key just saved in the app applies within moments. */
export async function secret(name: string): Promise<string | undefined> {
  if (!cache || Date.now() - cache.at > 15_000) {
    cache = { at: Date.now(), keys: load().catch(() => { cache = null; return {}; }) };
  }
  return (await cache.keys)[name] || Deno.env.get(name) || undefined;
}

/** Forget the cache (after the app saves or removes a key, so the check that follows sees it). */
export const forgetSecrets = () => { cache = null; };
