// © Pexilim
import { capProblem, cost, pickModel } from "./models.ts";

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
  if (capProblem(opus, {}, usage) !== null || capProblem(opus, { daily_cap_usd: "x" }, usage) !== null) throw new Error("no cap but stopped");
});
