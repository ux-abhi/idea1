// © Pexilim
import { parseContentRequest, parseDrafts, parseIdeas } from "./input.ts";

Deno.test("content requests are checked at the boundary", () => {
  const ok = parseContentRequest({ idea: " Why I build Blink ", platforms: ["x", "linkedin", "x"] });
  if (typeof ok === "string" || ok.idea !== "Why I build Blink" || ok.platforms.length !== 2) throw new Error("valid request rejected");
  for (const bad of [null, { idea: "" , platforms: ["x"] }, { idea: "a", platforms: [] }, { idea: "a", platforms: ["tiktok"] },
                     { idea: "x".repeat(2001), platforms: ["x"] }, { idea: "a", platforms: ["x"], space_id: "1; drop" }]) {
    if (typeof parseContentRequest(bad) !== "string") throw new Error(`accepted ${JSON.stringify(bad)?.slice(0, 60)}`);
  }
});

Deno.test("drafts keep only asked-for platforms and clean hashtags", () => {
  const drafts = parseDrafts({ drafts: [
    { platform: "x", format: "thread", hook: "h", body: "b", parts: ["1", 2, "3"], hashtags: ["#build in public", "ai"] },
    { platform: "instagram", format: "carousel", hook: "h", body: "b", parts: [], hashtags: [] }, // not asked
    { platform: "x", format: "tweetstorm", hook: "h", body: "b", parts: [], hashtags: [] }, // bad format
  ] }, ["x"]);
  if (drafts.length !== 1 || drafts[0].parts.length !== 2 || drafts[0].hashtags[0] !== "buildinpublic") throw new Error(JSON.stringify(drafts));
  if (parseDrafts(null, ["x"]).length !== 0) throw new Error("garbage accepted");
});

Deno.test("ideas mode needs no idea text and keeps only clean ideas", () => {
  const ok = parseContentRequest({ mode: "ideas", platforms: ["instagram"] });
  if (typeof ok === "string" || ok.mode !== "ideas") throw new Error("ideas without text rejected");
  if (typeof parseContentRequest({ mode: "drafts", idea: " ", platforms: ["x"] }) !== "string") throw new Error("empty draft idea accepted");
  if (typeof parseContentRequest({ mode: "spam", idea: "a", platforms: ["x"] }) !== "string") throw new Error("bad mode accepted");
  const ideas = parseIdeas({ ideas: [
    { title: "3 UX mistakes in checkout", hook: "Your checkout loses 1 in 3", platform: "instagram", format: "reel_script", why: "saves" },
    { title: "", hook: "h", platform: "instagram", format: "post", why: "w" },
    { title: "t", hook: "h", platform: "x", format: "post", why: "w" }, // not asked
  ] }, ["instagram"]);
  if (ideas.length !== 1 || ideas[0].format !== "reel_script") throw new Error(JSON.stringify(ideas));
});
