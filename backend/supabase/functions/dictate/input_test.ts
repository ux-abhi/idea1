// © Pexilim
import { assertEquals } from "jsr:@std/assert@1";
import { firstVideo, parseDictation, parsePlan, pickLanguage, whisperHints } from "./input.ts";

Deno.test("dictation requests are checked at the boundary", () => {
  const ok = parseDictation({ audio: btoa("abc"), language: "hi-IN" });
  if (typeof ok === "string" || ok.audio?.length !== 3) throw new Error("valid request rejected");
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

Deno.test("plans keep known actions and web links only", () => {
  const plan = parsePlan(JSON.stringify({
    actions: [
      { type: "quit_app", app: "Figma" },
      { type: "open_url", url: "javascript:alert(1)" }, // not a web link: dropped
      { type: "open_url", url: "https://example.com", app: "Google Chrome" },
      { type: "play", query: "Alphas", app: "Google Chrome" },
      { type: "run_shell", command: "rm -rf ~" }, // fifth: over the limit of 4, and unknown anyway
    ],
    say: "Okay, done.",
  }));
  assertEquals(plan.actions, [
    { type: "quit_app", app: "Figma" },
    { type: "open_url", url: "https://example.com", app: "Google Chrome" },
    { type: "play", query: "Alphas", app: "Google Chrome" },
  ]);
  assertEquals(plan.say, "Okay, done.");
  assertEquals(parsePlan('```json\n{"actions":[],"say":"Hi"}\n```').say, "Hi"); // fenced replies still read
  assertEquals(parseDictation({ text: " open Figma ", language: "en-US", mode: "command" }),
    { text: "open Figma", language: "en-US", mode: "command" });
  assertEquals(parsePlan("not json"), { actions: [], say: "Sorry, I didn't get that." });
  assertEquals(firstVideo('x"videoId":"dQw4w9WgXcQ"y'), "dQw4w9WgXcQ");
  assertEquals(parseDictation({ audio: "AA==", language: "en-US", mode: "shell" }), "mode must be type or command.");
});
