// © Pexilim
// Checks for the google function: everything from a client or from Google is checked here before use.

/** The smallest scopes for /meet: create events (with Meet links and invites) and know which account it is. */
export const SCOPES = "openid email https://www.googleapis.com/auth/calendar.events";

/** Google's consent page. offline + consent, so Google returns a refresh token every time the owner connects. */
export function consentURL(clientId: string, callback: string, state: string): string {
  const q = new URLSearchParams({
    client_id: clientId, redirect_uri: callback, response_type: "code", scope: SCOPES,
    access_type: "offline", prompt: "consent", include_granted_scopes: "true", state,
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${q}`;
}

/** The account's email from the id_token Google's token endpoint just returned to us over TLS (OIDC §3.1.3.7: a
 *  token received directly from the token endpoint needn't have its signature checked). */
export function emailFromIdToken(idToken: unknown): string | null {
  if (typeof idToken !== "string") return null;
  try {
    const part = idToken.split(".")[1].replaceAll("-", "+").replaceAll("_", "/");
    const claims = JSON.parse(atob(part.padEnd(part.length + (4 - part.length % 4) % 4, "=")));
    return typeof claims.email === "string" && claims.email.includes("@") && claims.email.length <= 320 ? claims.email : null;
  } catch {
    return null;
  }
}

export interface Meet { title: string; start: Date; minutes: number; timeZone: string; guests: string[] }

/** Same rule as the app's QuickCommand.isEmail, so the card never offers an address the server refuses after Touch ID. */
export const EMAIL = /^[^\s@<>,;"]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$/;

/** A signed "meet.create" payload, checked again before anything goes to Google. A string is the problem. */
export function parseMeet(payload: unknown, now = new Date()): Meet | string {
  const p = (payload ?? {}) as Record<string, unknown>;
  const title = typeof p.meet_title === "string" ? p.meet_title.trim() : "";
  if (!title || title.length > 200) return "The meeting needs a title of up to 200 characters.";
  const start = typeof p.start === "string" ? new Date(p.start) : new Date(NaN);
  if (isNaN(start.getTime())) return "The meeting needs a start time.";
  if (start.getTime() < now.getTime() - 10 * 60_000) return "That time has passed. Pick a new one.";
  if (start.getTime() > now.getTime() + 400 * 86_400_000) return "Pick a time within the next year.";
  const minutes = p.minutes;
  if (!Number.isInteger(minutes) || (minutes as number) < 5 || (minutes as number) > 480) return "A meeting lasts 5 minutes to 8 hours.";
  const timeZone = typeof p.time_zone === "string" ? p.time_zone : "";
  try {
    new Intl.DateTimeFormat("en", { timeZone });
  } catch {
    return "Unknown time zone.";
  }
  if (!timeZone) return "Unknown time zone.";
  const guests = Array.isArray(p.guests) ? p.guests : [];
  if (guests.length < 1 || guests.length > 20) return "Invite 1 to 20 people.";
  const clean: string[] = [];
  for (const g of guests) {
    if (typeof g !== "string" || g.length > 320 || !EMAIL.test(g.trim())) return `“${String(g).slice(0, 80)}” isn't an email address.`;
    const email = g.trim().toLowerCase();
    if (!clean.includes(email)) clean.push(email);
  }
  return { title, start, minutes: minutes as number, timeZone, guests: clean };
}

/** The Calendar event id for an action: its UUID's hex (Google allows 0-9 a-v), so a retry can't make a second event. */
export const eventId = (actionId: string) => actionId.replaceAll("-", "").toLowerCase();

/** The Calendar API event, with the action's id as both the event id and the Meet request id. */
export function eventBody(meet: Meet, requestId: string): Record<string, unknown> {
  const end = new Date(meet.start.getTime() + meet.minutes * 60_000);
  return {
    id: eventId(requestId),
    summary: meet.title,
    start: { dateTime: meet.start.toISOString(), timeZone: meet.timeZone },
    end: { dateTime: end.toISOString(), timeZone: meet.timeZone },
    attendees: meet.guests.map((email) => ({ email })),
    conferenceData: { createRequest: { requestId, conferenceSolutionKey: { type: "hangoutsMeet" } } },
  };
}
