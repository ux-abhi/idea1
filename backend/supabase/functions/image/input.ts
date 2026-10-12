// © Pexilim
// The trust boundary for image making: what the owner asks for, and how many images today.

export const DAILY_IMAGES = 100; // ~58 neurons each at 1024×1024: well inside Cloudflare's free 10,000 a day

export type ImageRequest = { subject: string; kind: "cover" | "background" };

/** The post's hook or idea, short and plain; kind picks the style. */
export function parseImageRequest(body: unknown): ImageRequest | string {
  const { subject, kind = "cover" } = (body ?? {}) as Record<string, unknown>;
  if (typeof subject !== "string" || !subject.trim()) return "subject is required.";
  if (subject.length > 500) return "subject is longer than 500 characters.";
  if (kind !== "cover" && kind !== "background") return "kind must be cover or background.";
  return { subject: subject.trim(), kind };
}

/** A text-free image prompt: slide and cover text is drawn crisply on the Mac, not by the image model. */
export function imagePrompt(request: ImageRequest): string {
  const style = request.kind === "background"
    ? "Abstract, calm background for a social media carousel: soft gradients and simple shapes, lots of empty space for text, muted modern colours."
    : "Clean editorial illustration for a social media post, modern and minimal, one clear subject, soft light, muted modern colours.";
  return `${style} Theme: ${request.subject.replace(/[\r\n]+/g, " ")}. No text, no letters, no words, no logos, no watermarks.`;
}
