// © Pexilim
import { parseContentRequest, parseDrafts } from "./input.ts";

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
