// © Pexilim
import { parseAnalysis, parseHandle, score, toRows } from "./input.ts";

Deno.test("handles come from @names, plain names or profile links only", () => {
  for (const [input, want] of [["@YourName", "yourname"], ["yourname", "yourname"], ["https://www.instagram.com/yourname/", "yourname"],
                               ["@yourname on Instagram: UX tips", "yourname"], ["not a handle!", null], ["", null], [5, null]] as const) {
    if (parseHandle(input) !== want) throw new Error(`${input} → ${parseHandle(input)}`);
  }
});

Deno.test("only the page's own well-formed posts become rows", () => {
  const rows = toRows([
    { url: "https://www.instagram.com/p/ABC123/", ownerUsername: "YourName", type: "Sidecar", caption: "tips", likesCount: 10, commentsCount: 2, timestamp: "2026-10-01T10:00:00.000Z" },
    { url: "https://www.instagram.com/reel/XYZ/", ownerUsername: "yourname", type: "Video", likesCount: -1, videoViewCount: 900 },
    { url: "https://evil.example/p/1/", ownerUsername: "yourname" },
    { url: "https://www.instagram.com/p/OTHER/", ownerUsername: "someoneelse" },
  ], "yourname");
  if (rows.length !== 2 || rows[0].kind !== "carousel" || rows[1].likes !== null || rows[1].views !== 900) throw new Error(JSON.stringify(rows));
  if (score(rows[0]) !== 16 || score(rows[1]) !== 90) throw new Error("score");
  if (toRows("nope", "yourname").length !== 0) throw new Error("garbage accepted");
});

Deno.test("analysis is trimmed and needs something useful", () => {
  const a = parseAnalysis({ voice: { page: "UX tips", audience: "devs", topics: "forms", tone: "dry" }, works: ["Before/after", 3], avoid: [] });
  if (!a || a.works.length !== 1) throw new Error(JSON.stringify(a));
  if (parseAnalysis({ voice: {}, works: [] }) !== null || parseAnalysis(null) !== null) throw new Error("empty analysis accepted");
});
