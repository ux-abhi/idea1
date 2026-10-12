// © Pexilim
// The sign-in helper (owner decision 2026-10-12): the one server piece Pexilim runs for other owners. It lets
// "Sign in with Supabase" work from a downloaded app, which can't keep an OAuth client secret. It stores nothing and
// logs no codes or tokens:
//   GET  /signin/start     The app opens this in the browser; it forwards to Supabase's consent page (so the app
//                          needs only this helper's address, not the client id).
//   GET  /signin/callback  Supabase sends the browser here after consent; it bounces to blink://signin with the code.
//   POST /signin/token     The app sends the code and its PKCE verifier; the helper adds the client secret, asks
//                          Supabase for a token and returns only the short-lived access token (never a refresh token).
// The tokens act on the owner's own Supabase account; Blink uses them once to set up their server, then drops them.
import { appRedirect, consentURL, parseExchange } from "./input.ts";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const id = Deno.env.get("SUPABASE_OAUTH_CLIENT_ID"), secret = Deno.env.get("SUPABASE_OAUTH_CLIENT_SECRET");
  if (!id || !secret) return json(503, { error: "Sign in with Supabase isn't set up on this helper yet." });
  // Must match the redirect URL registered on the OAuth app exactly.
  const callback = `${Deno.env.get("SUPABASE_URL")}/functions/v1/signin/callback`;

  if (req.method === "GET" && url.pathname.endsWith("/start")) {
    const to = consentURL(url.searchParams, id, callback);
    return to ? Response.redirect(to, 302) : new Response("This sign-in link is not valid. Start again from Blink.", { status: 400 });
  }

  if (req.method === "GET" && url.pathname.endsWith("/callback")) {
    const to = appRedirect(url.searchParams);
    if (!to) return new Response("This sign-in link is not valid. Start again from Blink.", { status: 400 });
    // A tiny page, in case the browser asks before opening Blink.
    const href = to.replaceAll("&", "&amp;");
    return new Response(`<!doctype html><meta charset="utf-8"><title>Back to Blink</title><meta http-equiv="refresh" content="0;url=${href}">` +
      `<p style="font:16px -apple-system;margin:40px">Opening Blink… <a href="${href}">Click here</a> if nothing happens.</p>`,
      { status: 302, headers: { Location: to, "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } });
  }

  if (req.method === "POST" && url.pathname.endsWith("/token")) {
    const exchange = parseExchange(await req.json().catch(() => null));
    if (typeof exchange === "string") return json(400, { error: exchange });
    const form = new URLSearchParams({ grant_type: "authorization_code", code: exchange.code, code_verifier: exchange.verifier, redirect_uri: callback });
    const response = await fetch("https://api.supabase.com/v1/oauth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json", Authorization: `Basic ${btoa(`${id}:${secret}`)}` },
      body: form,
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) return json(response.status === 400 ? 400 : 502, { error: "Supabase didn't accept the sign-in. Start again from Blink." });
    const { access_token, expires_in } = body as Record<string, unknown>;
    return json(200, { access_token, expires_in });
  }

  return json(404, { error: "Not found." });
});
