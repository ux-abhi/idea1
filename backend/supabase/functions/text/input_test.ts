// © Pexilim
import { groqCostUSD, parseTextRequest } from "./input.ts";

Deno.test("text requests are checked at the boundary", () => {
  const ok = parseTextRequest({ task: "fix", text: "teh cat" });
  if (typeof ok === "string" || ok.task !== "fix") throw new Error("valid request rejected");
  for (const bad of [null, { task: "translate", text: "x" }, { task: "fix", text: " " }, { task: "fix", text: "x".repeat(20_001) }]) {
    if (typeof parseTextRequest(bad) !== "string") throw new Error(`accepted ${JSON.stringify(bad)?.slice(0, 40)}`);
  }
});

Deno.test("cost meter uses gpt-oss-20b prices", () => {
  if (groqCostUSD(1_000_000, 1_000_000) !== 0.375) throw new Error("wrong price");
});
