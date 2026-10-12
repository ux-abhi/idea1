// © Pexilim
import { capProblem, claudeUsageCost, cost, pickModel } from "./models.ts";

Deno.test("only listed models are ever picked", () => {
  if (pickModel({ chat: "openai/gpt-oss-120b" }, "chat").provider !== "groq") throw new Error("valid choice ignored");
  if (pickModel({ chat: "evil/model" }, "chat").id !== "claude-opus-5-5") throw new Error("unlisted model accepted");
  if (pickModel(null, "content", "claude-sonnet-5-5").id !== "claude-sonnet-5-5") throw new Error("env default ignored");
  if (pickModel({ chat: "openai/gpt-oss-20b" }, "content").id !== "claude-opus-5-5") throw new Error("feature mixed up");
  if (cost(pickModel(null, "chat"), 1_000_000, 0) !== 4) throw new Error("cost wrong");
});

Deno.test("the daily Claude limit stops Claude only", () => {
  const opus = pickModel(null, "chat"), groq = pickModel({ chat: "openai/gpt-oss-120b" }, "chat");
  const usage = [{ model: "claude-opus-5-5", cost_usd: "1.5" }, { model: "openai/gpt-oss-120b", cost_usd: 9 }, { model: "claude-haiku-5-5", cost_usd: 0.6 }];
  if (capProblem(opus, { daily_cap_usd: 2 }, usage) === null) throw new Error("over the cap but allowed");
  if (capProblem(opus, { daily_cap_usd: 3 }, usage) !== null) throw new Error("under the cap but stopped (Groq spend counted?)");
  const sol = pickModel({ chat: "openai/gpt-6.1-sol" }, "chat");
  if (sol.provider !== "openrouter" || capProblem(sol, { daily_cap_usd: 2 }, [...usage, { model: "openai/gpt-6.1-sol", cost_usd: 0.1 }]) === null) {
    throw new Error("OpenRouter spend must count toward the paid limit");
  }
  if (capProblem(groq, { daily_cap_usd: 0.01 }, usage) !== null) throw new Error("free model stopped");
  if (capProblem(opus, {}, usage) !== null || capProblem(opus, { daily_cap_usd: "x" }, usage) !== null) throw new Error("under the default cap but stopped");
});

Deno.test("with no limit set, the server default ($5) applies; the owner's own limit wins; Groq is never capped", () => {
  const opus = pickModel(null, "chat"), groq = pickModel({ chat: "openai/gpt-oss-120b" }, "chat");
  const spent = [{ model: "claude-opus-5-5", cost_usd: 6 }];
  if (capProblem(opus, null, spent, undefined) === null || capProblem(opus, {}, spent, undefined) === null) throw new Error("no setting: default cap not applied");
  if (capProblem(opus, { daily_cap_usd: 10 }, spent, undefined) !== null) throw new Error("owner's higher limit ignored");
  if (capProblem(opus, { daily_cap_usd: 1 }, [{ model: "claude-opus-5-5", cost_usd: 2 }], "20") === null) throw new Error("owner's lower limit ignored");
  if (capProblem(opus, null, spent, "20") !== null) throw new Error("server default ignored");
  if (capProblem(groq, null, spent, undefined) !== null) throw new Error("Groq capped");
});

Deno.test("Claude cache writes cost 1.25x and cache reads 0.1x", () => {
  const opus = pickModel(null, "chat"); // $4 in, $20 out per million
  const usd = claudeUsageCost(opus, { input_tokens: 1_000_000, cache_creation_input_tokens: 1_000_000, cache_read_input_tokens: 1_000_000, output_tokens: 1_000_000 });
  if (Math.abs(usd - (4 + 5 + 0.4 + 20)) > 1e-9) throw new Error(`wrong cost ${usd}`);
});
