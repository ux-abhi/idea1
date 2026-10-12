// © Pexilim
// The trust boundary for content drafting, kept free of server code so it can be tested on its own.

export const PLATFORMS = ["instagram", "linkedin", "x"] as const;
export type Platform = typeof PLATFORMS[number];
export const FORMATS = ["caption", "carousel", "reel_script", "post", "thread"] as const;
export type Format = typeof FORMATS[number];

export type ContentRequest = { mode: "drafts" | "ideas"; idea: string; platforms: Platform[]; spaceID: string | null };
export type Idea = { title: string; hook: string; platform: Platform; format: Format; why: string };
export type Draft = { platform: Platform; format: Format; hook: string; body: string; parts: string[]; hashtags: string[] };

export const MAX_IDEA = 2000;

/** Returns the checked request, or a sentence saying what's wrong. */
export function parseContentRequest(body: unknown): ContentRequest | string {
  if (typeof body !== "object" || body === null) return "Send a JSON body.";
  const { idea = "", platforms, space_id = null, mode = "drafts" } = body as Record<string, unknown>;
  if (mode !== "drafts" && mode !== "ideas") return "mode must be drafts or ideas.";
  if (typeof idea !== "string") return "idea must be text.";
  // Ideas can start from nothing (the owner's page and topics); drafts need something to write about.
  if (mode === "drafts" && idea.trim().length === 0) return "idea is required.";
  if (idea.length > MAX_IDEA) return `idea is longer than ${MAX_IDEA} characters.`;
  if (!Array.isArray(platforms) || platforms.length === 0 || platforms.some((p) => !PLATFORMS.includes(p as Platform))) {
    return "platforms must list instagram, linkedin and/or x.";
  }
  if (space_id !== null && (typeof space_id !== "string" || !/^[0-9a-f-]{36}$/i.test(space_id))) return "space_id must be a uuid.";
  return { mode, idea: idea.trim(), platforms: [...new Set(platforms as Platform[])], spaceID: space_id as string | null };
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

/** The ideas list, checked like drafts: only asked-for platforms and known formats, at most 8. */
export function parseIdeas(output: unknown, asked: Platform[]): Idea[] {
  const ideas = (output as { ideas?: unknown })?.ideas;
  if (!Array.isArray(ideas)) return [];
  const clean: Idea[] = [];
  for (const i of ideas) {
    const { title, hook, platform, format, why } = (i ?? {}) as Record<string, unknown>;
    if (!asked.includes(platform as Platform) || !FORMATS.includes(format as Format)) continue;
    if (typeof title !== "string" || !title.trim() || typeof hook !== "string" || typeof why !== "string") continue;
    clean.push({ title: title.trim().slice(0, 300), hook: hook.slice(0, 300), platform: platform as Platform, format: format as Format, why: why.slice(0, 300) });
  }
  return clean.slice(0, 8);
}
