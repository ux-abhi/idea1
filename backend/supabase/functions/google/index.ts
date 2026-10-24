// © Pexilim
// Google Calendar for /meet (ARCHITECTURE §34), on the owner's own server. Two ways to connect: one click with Blink's
// built-in Desktop client (the Mac gets the code over 127.0.0.1 with PKCE, /exchange finishes here), or the owner's own
// Web client (GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET, /start + /callback). Deployed with --no-verify-jwt because Google's
// redirect is a plain browser request; the other routes check the caller themselves.
//   POST /google/exchange  One click: the Mac's code and PKCE verifier become a refresh token in Vault.
//   POST /google/start     The app asks for Google's consent page; a one-time state ties the answer to this owner.
//   GET  /google/callback  Google sends the browser here; the refresh token goes to Vault, never to a device.
//   POST /google/disconnect Revokes Blink's access at Google, then deletes the token and the link.
//   POST /google/meet      Creates the event with a Meet link and emails the guests, only for a red "meet.create"
//                          action the owner approved with Touch ID, exactly as signed.
// shortcut: calls Google Calendar's REST API directly instead of the §34 connector gateway; move it behind the gateway
// when a second Google feature (Gmail, Drive, calendar reads) needs the same connection.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { consentURL, emailFromIdToken, eventBody, eventId, parseExchange, parseMeet } from "./input.ts";
import { secret } from "../_shared/secrets.ts";
import { isServerOwner } from "../_shared/owner.ts";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

const page = (text: string, status = 200) =>
  new Response(`<!doctype html><meta charset="utf-8"><title>Blink</title>` +
    `<p style="font:16px -apple-system;margin:40px">${text}</p>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } });

const sha256 = async (text: string) => new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
const bytea = (bytes: Uint8Array) => "\\x" + Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  // Disconnect works even when the Google app keys were removed: it needs only the owner's login.
  if (req.method === "POST" && url.pathname.endsWith("/disconnect")) {
    const { data: { user } } = await admin.auth.getUser((req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, ""));
    if (!user) return json(401, { error: "signed out" });
    if (!(await isServerOwner(admin, user.id))) return json(403, { error: "Only this server's owner can change Google." });
    const token = (await admin.rpc("google_token", { owner: user.id })).data;
    // Best effort: an already-revoked token is fine; the copy on this server goes either way.
    if (typeof token === "string") await fetch("https://oauth2.googleapis.com/revoke", { method: "POST", body: new URLSearchParams({ token }) }).catch(() => {});
    const { error } = await admin.rpc("google_disconnect", { owner: user.id });
    return error ? json(500, { error: "Couldn't disconnect. Try again." }) : json(200, { disconnected: true });
  }

  // The owner's own Web client, or Blink's built-in Desktop client; a token is refreshed with the one that made it.
  const client = async (via: "own" | "blink") => {
    const [id, sec] = via === "blink"
      ? [await secret("GOOGLE_DESKTOP_CLIENT_ID"), await secret("GOOGLE_DESKTOP_CLIENT_SECRET")]
      : [await secret("GOOGLE_CLIENT_ID"), await secret("GOOGLE_CLIENT_SECRET")];
    return id && sec ? { id, secret: sec } : null;
  };
  const noOwnApp = "Add your Google app's client ID and secret in Settings › Connections first.";
  const callback = `${Deno.env.get("SUPABASE_URL")}/functions/v1/google/callback`;
  // Google's answer to a code exchange: the refresh token, the account, and that calendar access was really granted.
  const received = async (tokenRes: Response) => {
    const tokens = await tokenRes.json().catch(() => ({}));
    const account = emailFromIdToken(tokens.id_token);
    // Each permission can be unticked on Google's page: without calendar events, /meet could never work.
    const granted = typeof tokens.scope === "string" ? tokens.scope.split(" ") : [];
    return tokenRes.ok && typeof tokens.refresh_token === "string" && account &&
        granted.includes("https://www.googleapis.com/auth/calendar.events")
      ? { token: tokens.refresh_token as string, account } : null;
  };

  if (req.method === "GET" && url.pathname.endsWith("/callback")) {
    const code = url.searchParams.get("code"), state = url.searchParams.get("state");
    if (!code || !state || code.length > 2048 || state.length > 200) {
      return page("Google didn't connect. Start again from Blink › Settings › Connections.", 400);
    }
    // One use only, and only within its 10 minutes.
    const { data: rows } = await admin.from("google_oauth_state").delete()
      .eq("state_hash", bytea(await sha256(state))).gt("expires_at", new Date().toISOString()).select("owner_id");
    const owner = rows?.[0]?.owner_id;
    if (!owner) return page("This link has expired. Start again from Blink › Settings › Connections.", 400);
    const own = await client("own");
    if (!own) return page(noOwnApp, 503);

    const got = await received(await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      body: new URLSearchParams({ code, client_id: own.id, client_secret: own.secret, redirect_uri: callback, grant_type: "authorization_code" }),
    }));
    if (!got) return page("Google didn't give Blink calendar access. Start again from Blink and leave calendar access ticked.", 502);
    const { error } = await admin.rpc("google_connect", { owner, account: got.account, token: got.token, via: "own" });
    if (error) return page("Couldn't save the connection on your server. Try again.", 500);
    return page(`Google is connected (${got.account.replaceAll("<", "&lt;")}). You can close this tab and go back to Blink.`);
  }

  if (req.method !== "POST") return json(405, { error: "POST only" });
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user) return json(401, { error: "signed out" });
  if (!(await isServerOwner(admin, user.id))) return json(403, { error: "Only this server's owner can use Google." });

  if (url.pathname.endsWith("/exchange")) {
    const blink = await client("blink");
    if (!blink) return json(503, { error: "This copy of Blink can't connect Google in one click. Use your own Google app under Advanced." });
    const exchange = parseExchange(await req.json().catch(() => null));
    if (typeof exchange === "string") return json(400, { error: exchange });
    const got = await received(await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      body: new URLSearchParams({ code: exchange.code, code_verifier: exchange.verifier, redirect_uri: exchange.redirect,
                                  client_id: blink.id, client_secret: blink.secret, grant_type: "authorization_code" }),
    }));
    if (!got) return json(502, { error: "Google didn't give Blink calendar access. Try again and leave calendar access ticked." });
    const { error } = await admin.rpc("google_connect", { owner: user.id, account: got.account, token: got.token, via: "blink" });
    return error ? json(500, { error: "Couldn't save the connection on your server. Try again." }) : json(200, { account: got.account });
  }

  if (url.pathname.endsWith("/start")) {
    const own = await client("own");
    if (!own) return json(503, { error: noOwnApp });
    const state = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
      .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
    await admin.from("google_oauth_state").delete().lt("expires_at", new Date().toISOString());
    const { error } = await admin.from("google_oauth_state").insert({
      state_hash: bytea(await sha256(state)), owner_id: user.id, expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
    });
    if (error) return json(500, { error: "Couldn't start. Try again." });
    return json(200, { url: consentURL(own.id, callback, state) });
  }

  if (url.pathname.endsWith("/meet")) {
    const body = await req.json().catch(() => null);
    if (typeof body?.action_id !== "string") return json(400, { error: "action_id is required" });
    const { data: action } = await admin.from("action").select("id, status, payload, result")
      .eq("id", body.action_id).eq("owner_id", user.id).eq("kind", "meet.create").eq("risk", "red").maybeSingle();
    if (!action) return json(404, { error: "No such meeting." });
    if (action.status === "done" && action.result?.meet_url) return json(200, action.result); // a retry after a lost reply
    // Status codes the app reads: 412 = fix something and Create again (the approval still stands);
    // 400/409 = this approval is spent, a changed card needs a new one.
    const meet = parseMeet(action.payload);
    if (typeof meet === "string") {
      await admin.from("action").update({ status: "failed", result: { error: meet } }).eq("id", action.id).eq("status", "approved");
      return json(400, { error: meet });
    }

    const token = (await admin.rpc("google_token", { owner: user.id })).data;
    if (typeof token !== "string") return json(412, { error: "Connect Google first, in Settings › Connections." });
    const { data: link } = await admin.from("google_link").select("client").eq("owner_id", user.id).maybeSingle();
    const creds = await client(link?.client === "blink" ? "blink" : "own");
    if (!creds) return json(412, { error: "The Google app this connection was made with is missing. Connect Google again." });

    // Claimed before calling Google (approved → done, conditional), so two calls at once can't both go ahead.
    const { data: claimed } = await admin.from("action").update({ status: "done" })
      .eq("id", action.id).eq("status", "approved").select("id");
    if (!claimed?.length) return json(409, { error: "This meeting isn't approved." });
    // Not created: back to approved, so Create again retries without a second Touch ID. The event id is the action's,
    // so a retry after Google did create it finds that event instead of inviting everyone twice.
    const retry = async (error: string) => {
      await admin.from("action").update({ status: "approved" }).eq("id", action.id).eq("status", "done");
      return json(412, { error });
    };

    const refreshed = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      body: new URLSearchParams({ refresh_token: token, client_id: creds.id, client_secret: creds.secret, grant_type: "refresh_token" }),
    });
    const access = (await refreshed.json().catch(() => ({}))).access_token;
    if (!refreshed.ok || typeof access !== "string") return retry("Google signed Blink out. Connect Google again in Settings › Connections, then Create again.");

    const calendar = "https://www.googleapis.com/calendar/v3/calendars/primary/events";
    let created = await fetch(`${calendar}?conferenceDataVersion=1&sendUpdates=all`,
      { method: "POST", headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
        body: JSON.stringify(eventBody(meet, action.id)) });
    if (created.status === 409) { // made on an earlier try whose answer got lost
      created = await fetch(`${calendar}/${eventId(action.id)}`, { headers: { Authorization: `Bearer ${access}` } });
    }
    const event = await created.json().catch(() => ({}));
    if (!created.ok || typeof event.id !== "string") {
      // Google's own reason, so the owner and the logs can see what to fix. Never holds tokens (they are only sent);
      // it may name a guest address, which stays in the owner's own logs.
      const reason = typeof event?.error?.message === "string" ? event.error.message.slice(0, 300) : `HTTP ${created.status}`;
      console.error("calendar insert failed", created.status, reason);
      return retry(`Google Calendar didn't create the meeting: ${reason}`);
    }
    const result = {
      event_id: event.id,
      meet_url: typeof event.hangoutLink === "string" ? event.hangoutLink : null,
      html_link: typeof event.htmlLink === "string" ? event.htmlLink : null,
    };
    // The meeting exists and guests are invited: the owner gets the link even if saving it here fails.
    const { error: saveError } = await admin.from("action").update({ result }).eq("id", action.id);
    if (saveError) console.error("meet result not saved", saveError.message);
    return json(200, result);
  }

  return json(404, { error: "Not found" });
});
