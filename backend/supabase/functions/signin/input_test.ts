// © Pexilim
import { appRedirect, consentURL, parseExchange } from "./input.ts";

Deno.test("only well-formed exchanges pass", () => {
  const verifier = "a".repeat(43);
  const ok = parseExchange({ code: "abc123def456", code_verifier: verifier });
  if (typeof ok === "string" || ok.code !== "abc123def456") throw new Error(JSON.stringify(ok));
  if (typeof parseExchange({ code: "abc123def456", code_verifier: "short" }) !== "string") throw new Error("short verifier accepted");
  if (typeof parseExchange({ code: "x y", code_verifier: verifier }) !== "string") throw new Error("bad code accepted");
  if (typeof parseExchange({ refresh_token: "r".repeat(20) }) !== "string") throw new Error("refresh accepted: Blink never refreshes");
});

Deno.test("the callback hands only the code and state back to the app", () => {
  const to = appRedirect(new URLSearchParams({ code: "abc123def456", state: "s".repeat(32) }));
  if (to !== `blink://signin?code=abc123def456&state=${"s".repeat(32)}`) throw new Error(String(to));
  if (appRedirect(new URLSearchParams({ code: "abc123def456" })) !== null) throw new Error("missing state accepted");
  if (!appRedirect(new URLSearchParams({ error: "access_denied" }))?.startsWith("blink://signin?error=")) throw new Error("error not passed");
});

Deno.test("the start link only carries a proper S256 challenge and state to Supabase", () => {
  const ok = consentURL(new URLSearchParams({ challenge: "c".repeat(43), state: "s".repeat(32) }), "client-1", "https://h/cb");
  if (!ok?.startsWith("https://api.supabase.com/v1/oauth/authorize?") || !ok.includes("code_challenge_method=S256") || !ok.includes("client_id=client-1")) {
    throw new Error(String(ok));
  }
  if (consentURL(new URLSearchParams({ challenge: "short", state: "s".repeat(32) }), "c", "https://h/cb") !== null) throw new Error("bad challenge accepted");
});
