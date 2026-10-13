// © Pexilim
// The trust boundary for the sign-in helper: only well-formed codes and verifiers are passed on.

/** An OAuth exchange the app may ask for: a fresh code with its PKCE verifier (Blink never refreshes; it uses the
 *  token once, for setup). */
export type Exchange = { code: string; verifier: string };

const TOKENISH = /^[A-Za-z0-9._~+/=-]{8,4096}$/;
// RFC 7636: 43–128 characters from the unreserved set.
const VERIFIER = /^[A-Za-z0-9._~-]{43,128}$/;

export function parseExchange(body: unknown): Exchange | string {
  const { code, code_verifier } = (body ?? {}) as Record<string, unknown>;
  if (typeof code !== "string" || !TOKENISH.test(code)) return "Bad code.";
  if (typeof code_verifier !== "string" || !VERIFIER.test(code_verifier)) return "Bad code verifier.";
  return { code, verifier: code_verifier };
}

/** Where the browser goes after consent: back into the app, carrying only the one-time code and the app's state. */
export function appRedirect(params: URLSearchParams): string | null {
  const code = params.get("code"), state = params.get("state"), error = params.get("error");
  const goodState = !!state && /^[A-Za-z0-9_-]{16,128}$/.test(state);
  // Only a fixed word goes back, never Supabase's (or a stranger's) text, with the state so the app can check it.
  if (error) return `blink://signin?error=${error === "access_denied" ? "access_denied" : "failed"}${goodState ? `&state=${state}` : ""}`;
  if (!code || !TOKENISH.test(code) || !goodState) return null;
  return `blink://signin?code=${encodeURIComponent(code)}&state=${encodeURIComponent(state)}`;
}

/** Supabase's consent page for this app, with the app's PKCE challenge and state (both checked first). */
export function consentURL(params: URLSearchParams, clientID: string, callback: string): string | null {
  const challenge = params.get("challenge"), state = params.get("state");
  if (!challenge || !/^[A-Za-z0-9_-]{43}$/.test(challenge) || !state || !/^[A-Za-z0-9_-]{16,128}$/.test(state)) return null;
  const url = new URL("https://api.supabase.com/v1/oauth/authorize");
  url.search = new URLSearchParams({ client_id: clientID, redirect_uri: callback, response_type: "code",
    code_challenge: challenge, code_challenge_method: "S256", state }).toString();
  return url.toString();
}
