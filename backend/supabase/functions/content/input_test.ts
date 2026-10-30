// © Pexilim
import { ideaRows, parseContentRequest, parseDrafts, parseIdeas, parseQuestions } from "./input.ts";

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

Deno.test("the week plan keeps only ideas on the given days, in day order", () => {
  const days = ["2026-10-13", "2026-10-14"];
  const ok = parseContentRequest({ mode: "week", platforms: ["x"], days });
  if (typeof ok === "string" || ok.days.length !== 2) throw new Error("week request rejected");
  if (typeof parseContentRequest({ mode: "week", platforms: ["x"] }) !== "string") throw new Error("week without days accepted");
  if (typeof parseContentRequest({ mode: "drafts", idea: "a", platforms: ["x"], planned_for: "tomorrow" }) !== "string") throw new Error("bad planned_for");
  const ideas = parseIdeas({ ideas: [
    { title: "B", hook: "h", platform: "x", format: "post", why: "w", day: "2026-10-14" },
    { title: "A", hook: "h", platform: "x", format: "post", why: "w", day: "2026-10-13" },
    { title: "C", hook: "h", platform: "x", format: "post", why: "w", day: "2027-01-01" }, // not this week
  ] }, ["x"], days);
  if (ideas.map((i) => i.title).join() !== "A,B") throw new Error(JSON.stringify(ideas));
});

Deno.test("questions for the owner are short and at most three", () => {
  const q = parseQuestions({ questions: ["How many users?", "", 5, "Which city?", "When?", "Extra?"] });
  if (q.length !== 3 || q[0] !== "How many users?") throw new Error(JSON.stringify(q));
  if (parseQuestions({}).length !== 0) throw new Error("missing questions should be empty");
});

Deno.test("a week plan's ideas are kept on their days as ideas", () => {
  const rows = ideaRows([{ title: "Checkout mistakes", hook: "Stop losing buyers", platform: "x", format: "post", why: "Teaches one thing", day: "2026-11-02" }], null);
  if (rows[0].status !== "idea" || rows[0].planned_for !== "2026-11-02" || rows[0].body !== "Teaches one thing") throw new Error("idea row");
});
