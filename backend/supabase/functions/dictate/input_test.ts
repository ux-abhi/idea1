// © Pexilim
import { parseDictation, pickLanguage, whisperHints } from "./input.ts";

Deno.test("dictation requests are checked at the boundary", () => {
  const ok = parseDictation({ audio: btoa("abc"), language: "hi-IN" });
  if (typeof ok === "string" || ok.audio.length !== 3) throw new Error("valid request rejected");
  for (const bad of [null, { audio: "", language: "en-US" }, { audio: btoa("a"), language: 42 },
    { audio: "%%%", language: "en-US" }, { audio: "a".repeat(8_000_001), language: "en-US" }]) {
    if (typeof parseDictation(bad) !== "string") throw new Error(`accepted ${JSON.stringify(bad)?.slice(0, 40)}`);
  }
});

Deno.test("an unpicked language falls back by its prefix", () => {
  if (pickLanguage("hi") !== "hi-IN" || pickLanguage("de-AT") !== "de-DE" || pickLanguage("en-DE") !== "en-US") {
    throw new Error("fallback wrong");
  }
});

Deno.test("Hinglish gets no fixed language and a Roman-letter prompt", () => {
  const hints = whisperHints("hi-IN");
  if (hints.language || !hints.prompt?.includes("theek hai")) throw new Error("Hindi hints wrong");
  if (whisperHints("de-DE").language !== "de" || whisperHints("en-GB").language !== "en") throw new Error("fixed languages wrong");
});
