// © Pexilim
// The trust boundaries for reading the owner's page: the handle we ask Apify for, the posts it returns, and the analysis.

/** "@yourname", "yourname" or "https://www.instagram.com/yourname/" → "yourname"; null if it isn't a valid handle. */
export function parseHandle(input: unknown): string | null {
  if (typeof input !== "string") return null;
  const text = input.trim();
  const fromUrl = text.match(/instagram\.com\/([A-Za-z0-9._]{1,30})/i)?.[1];
  const handle = fromUrl ?? text.match(/@([A-Za-z0-9._]{1,30})/)?.[1] ?? text;
  return /^[A-Za-z0-9._]{1,30}$/.test(handle) ? handle.toLowerCase() : null;
}

export type PostRow = {
  platform: "instagram"; handle: string; url: string; kind: "image" | "video" | "carousel";
  caption: string; likes: number | null; comments: number | null; views: number | null; posted_at: string | null;
};

const count = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? Math.round(v) : null);

/** Apify's items → rows for social_post. Anything malformed or not from the asked-for page is dropped. */
export function toRows(items: unknown, handle: string): PostRow[] {
  if (!Array.isArray(items)) return [];
  const rows: PostRow[] = [];
  for (const item of items) {
    const i = (item ?? {}) as Record<string, unknown>;
    const url = typeof i.url === "string" ? i.url : "";
    if (!/^https:\/\/www\.instagram\.com\/(p|reel)\/[A-Za-z0-9_-]+\/?$/.test(url)) continue;
    if (typeof i.ownerUsername === "string" && i.ownerUsername.toLowerCase() !== handle) continue;
    const kind = i.type === "Video" ? "video" : i.type === "Sidecar" ? "carousel" : "image";
    const posted = typeof i.timestamp === "string" && !Number.isNaN(Date.parse(i.timestamp)) ? new Date(i.timestamp).toISOString() : null;
    rows.push({
      platform: "instagram", handle, url, kind,
      caption: typeof i.caption === "string" ? i.caption.slice(0, 5000) : "",
      likes: count(i.likesCount), comments: count(i.commentsCount), views: count(i.videoViewCount ?? i.videoPlayCount),
      posted_at: posted,
    });
  }
  return rows;
}

/** Likes plus 3× comments plus a tenth of views: a rough "this worked" score to rank posts. */
export function score(p: { likes: number | null; comments: number | null; views: number | null }): number {
  return (p.likes ?? 0) + 3 * (p.comments ?? 0) + (p.views ?? 0) / 10;
}

export type Analysis = {
  voice: { page: string; audience: string; topics: string; tone: string };
  works: string[]; avoid: string[];
};

/** The model's read of the page, trimmed to sane sizes; null if it's not the expected shape. */
export function parseAnalysis(output: unknown): Analysis | null {
  const o = (output ?? {}) as Record<string, unknown>;
  const v = (o.voice ?? {}) as Record<string, unknown>;
  const text = (x: unknown, n: number) => (typeof x === "string" ? x.trim().slice(0, n) : "");
  const list = (x: unknown) => (Array.isArray(x) ? x.filter((s): s is string => typeof s === "string" && !!s.trim()).slice(0, 5).map((s) => s.slice(0, 300)) : []);
  const analysis = {
    voice: { page: text(v.page, 500), audience: text(v.audience, 1000), topics: text(v.topics, 1000), tone: text(v.tone, 1000) },
    works: list(o.works), avoid: list(o.avoid),
  };
  return analysis.voice.page || analysis.works.length ? analysis : null;
}
