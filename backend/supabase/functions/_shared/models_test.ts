// © Pexilim
import { foldChunks, capProblem, claudeUsageCost, cost, customEndpoint, pickModel } from "./models.ts";

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

Deno.test("a streamed answer folds into one message, tool calls included", () => {
  const { message, usage } = foldChunks([
    { choices: [{ delta: { content: "Adding " } }] },
    { choices: [{ delta: { content: "it." , tool_calls: [{ index: 0, id: "call_1", function: { name: "propose_", arguments: '{"ti' } }] } }] },
    { choices: [{ delta: { tool_calls: [{ index: 0, function: { name: "task", arguments: 'tle":"Gym"}' } }] } }] },
    { choices: [], usage: { prompt_tokens: 10, completion_tokens: 4 } },
  ]);
  if (message.content !== "Adding it.") throw new Error(String(message.content));
  if (message.tool_calls?.[0].function.name !== "propose_task" || message.tool_calls[0].function.arguments !== '{"title":"Gym"}') throw new Error(JSON.stringify(message.tool_calls));
  if (usage.completion_tokens !== 4) throw new Error("usage");
  if (foldChunks([{ choices: [{ delta: { content: "Hi" } }] }]).message.tool_calls) throw new Error("no calls expected");
});

Deno.test("your own AI: an https address becomes its chat endpoint; anything else is refused", () => {
  if (customEndpoint("https://api.mistral.ai/v1/") !== "https://api.mistral.ai/v1/chat/completions") throw new Error("base");
  if (customEndpoint("https://x.example/v1/chat/completions") !== "https://x.example/v1/chat/completions") throw new Error("full");
  if (customEndpoint("http://localhost:11434/v1") !== null) throw new Error("plain http refused");
  if (customEndpoint("not a url") !== null || customEndpoint(undefined) !== null) throw new Error("junk refused");
});
