// © Pexilim
// The trust boundary for content drafting, kept free of server code so it can be tested on its own.

export const PLATFORMS = ["instagram", "linkedin", "x"] as const;
export type Platform = typeof PLATFORMS[number];
export const FORMATS = ["caption", "carousel", "reel_script", "post", "thread"] as const;
export type Format = typeof FORMATS[number];

export type ContentRequest = {
  mode: "drafts" | "ideas" | "week"; idea: string; platforms: Platform[]; spaceID: string | null;
  /** The owner's next 7 days (YYYY-MM-DD, in their time zone), for the week plan. */
  days: string[];
  /** Drafts written from a planned idea carry its day. */
  plannedFor: string | null;
};
export type Idea = { title: string; hook: string; platform: Platform; format: Format; why: string; day?: string };

const DAY = /^\d{4}-\d{2}-\d{2}$/;
export type Draft = { platform: Platform; format: Format; hook: string; body: string; parts: string[]; hashtags: string[] };

export const MAX_IDEA = 2000;

/** Returns the checked request, or a sentence saying what's wrong. */
export function parseContentRequest(body: unknown): ContentRequest | string {
  if (typeof body !== "object" || body === null) return "Send a JSON body.";
  const { idea = "", platforms, space_id = null, mode = "drafts", days = [], planned_for = null } = body as Record<string, unknown>;
  if (mode !== "drafts" && mode !== "ideas" && mode !== "week") return "mode must be drafts, ideas or week.";
  if (!Array.isArray(days) || days.length > 7 || days.some((d) => typeof d !== "string" || !DAY.test(d))) {
    return "days must be up to 7 dates like 2026-10-14.";
  }
  if (mode === "week" && days.length === 0) return "The week plan needs the next days.";
  if (planned_for !== null && (typeof planned_for !== "string" || !DAY.test(planned_for))) return "planned_for must be a date like 2026-10-14.";
  if (typeof idea !== "string") return "idea must be text.";
  // Ideas can start from nothing (the owner's page and topics); drafts need something to write about.
  if (mode === "drafts" && idea.trim().length === 0) return "idea is required.";
  if (idea.length > MAX_IDEA) return `idea is longer than ${MAX_IDEA} characters.`;
  if (!Array.isArray(platforms) || platforms.length === 0 || platforms.some((p) => !PLATFORMS.includes(p as Platform))) {
    return "platforms must list instagram, linkedin and/or x.";
  }
  if (space_id !== null && (typeof space_id !== "string" || !/^[0-9a-f-]{36}$/i.test(space_id))) return "space_id must be a uuid.";
  return {
    mode, idea: idea.trim(), platforms: [...new Set(platforms as Platform[])], spaceID: space_id as string | null,
    days: days as string[], plannedFor: planned_for as string | null,
  };
}

/** Claude's structured reply, checked again before anything is saved: only asked-for platforms, sane sizes. */
export function parseDrafts(output: unknown, asked: Platform[]): Draft[] {
  const drafts = (output as { drafts?: unknown })?.drafts;
  if (!Array.isArray(drafts)) return [];
  const clean: Draft[] = [];
  for (const d of drafts) {
    const { platform, format, hook, body, parts, hashtags } = (d ?? {}) as Record<string, unknown>;
    if (!asked.includes(platform as Platform) || !FORMATS.includes(format as Format)) continue;
    if (typeof hook !== "string" || typeof body !== "string" || !Array.isArray(parts) || !Array.isArray(hashtags)) continue;
    clean.push({
      platform: platform as Platform,
      format: format as Format,
      hook: hook.slice(0, 500),
      body: body.slice(0, 10000),
      parts: parts.filter((p): p is string => typeof p === "string").slice(0, 30).map((p) => p.slice(0, 2000)),
      hashtags: hashtags.filter((h): h is string => typeof h === "string").slice(0, 30)
        .map((h) => h.replace(/^#/, "").replace(/\s+/g, "").slice(0, 60)).filter(Boolean),
    });
  }
  return clean;
}

/** The ideas list, checked like drafts: only asked-for platforms and known formats, at most 8.
 *  For the week plan, each idea must fall on one of the given days; the list comes back in day order. */
export function parseIdeas(output: unknown, asked: Platform[], days: string[] = []): Idea[] {
  const ideas = (output as { ideas?: unknown })?.ideas;
  if (!Array.isArray(ideas)) return [];
  const clean: Idea[] = [];
  for (const i of ideas) {
    const { title, hook, platform, format, why, day } = (i ?? {}) as Record<string, unknown>;
    if (!asked.includes(platform as Platform) || !FORMATS.includes(format as Format)) continue;
    if (typeof title !== "string" || !title.trim() || typeof hook !== "string" || typeof why !== "string") continue;
    if (days.length > 0 && (typeof day !== "string" || !days.includes(day))) continue;
    clean.push({
      title: title.trim().slice(0, 300), hook: hook.slice(0, 300), platform: platform as Platform, format: format as Format,
      why: why.slice(0, 300), ...(days.length > 0 ? { day: day as string } : {}),
    });
  }
  if (days.length > 0) clean.sort((a, b) => (a.day ?? "").localeCompare(b.day ?? ""));
  return clean.slice(0, 8);
}

/** Up to 3 short questions the model wants answered for a stronger post (asking beats inventing). */
export function parseQuestions(output: unknown): string[] {
  const questions = (output as { questions?: unknown })?.questions;
  if (!Array.isArray(questions)) return [];
  return questions.filter((q): q is string => typeof q === "string" && !!q.trim()).slice(0, 3).map((q) => q.trim().slice(0, 300));
}
