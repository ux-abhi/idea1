// © Pexilim
import { imagePrompt, parseImageRequest } from "./input.ts";

Deno.test("image requests are short subjects with a known kind, and prompts never ask for text", () => {
  const ok = parseImageRequest({ subject: " 3 checkout mistakes ", kind: "background" });
  if (typeof ok === "string" || ok.subject !== "3 checkout mistakes") throw new Error("valid request rejected");
  for (const bad of [null, { subject: "" }, { subject: "x".repeat(501) }, { subject: "a", kind: "nsfw" }]) {
    if (typeof parseImageRequest(bad) !== "string") throw new Error(`accepted ${JSON.stringify(bad)?.slice(0, 40)}`);
  }
  const prompt = imagePrompt({ subject: "line one\nline two", kind: "cover" });
  if (!prompt.includes("No text") || prompt.includes("\n")) throw new Error(prompt);
});
