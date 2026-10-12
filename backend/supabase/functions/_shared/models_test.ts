// © Pexilim
import { cost, pickModel } from "./models.ts";

Deno.test("only listed models are ever picked", () => {
  if (pickModel({ chat: "openai/gpt-oss-120b" }, "chat").provider !== "groq") throw new Error("valid choice ignored");
  if (pickModel({ chat: "evil/model" }, "chat").id !== "claude-opus-5-5") throw new Error("unlisted model accepted");
  if (pickModel(null, "content", "claude-sonnet-5-5").id !== "claude-sonnet-5-5") throw new Error("env default ignored");
  if (pickModel({ chat: "openai/gpt-oss-20b" }, "content").id !== "claude-opus-5-5") throw new Error("feature mixed up");
  if (cost(pickModel(null, "chat"), 1_000_000, 0) !== 4) throw new Error("cost wrong");
});
