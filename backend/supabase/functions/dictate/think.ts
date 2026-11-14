// © Pexilim
// One short question to the model the owner picked for voice (Settings › Usage): Claude through Anthropic, anything
// else through its OpenAI-compatible endpoint. Throws a sentence the app can show.
import Anthropic from "npm:@anthropic-ai/sdk@0.128.0";
import { claudeUsageCost, compatible, cost, type Model } from "../_shared/models.ts";
import { secret } from "../_shared/secrets.ts";

export async function think(model: Model, system: string, user: string, json: boolean): Promise<{ text: string; inputTokens: number; outputTokens: number; usd: number }> {
  if (model.provider === "claude") {
    const apiKey = await secret("ANTHROPIC_API_KEY");
    if (!apiKey) throw new Error("Add your Anthropic API key in Blink › Settings › Connections, or pick another voice model in Settings › Usage.");
    const workspace = await secret("ANTHROPIC_WORKSPACE_ID");
    const client = new Anthropic({ apiKey, defaultHeaders: workspace ? { "anthropic-workspace-id": workspace } : undefined });
    try {
      const response = await client.messages.create({ model: model.id, max_tokens: 1024, system, messages: [{ role: "user", content: user }] });
      const usage = response.usage;
      return {
        text: response.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join(""),
        inputTokens: usage.input_tokens, outputTokens: usage.output_tokens, usd: claudeUsageCost(model, usage),
      };
    } catch (error) {
      if (error instanceof Anthropic.AuthenticationError) throw new Error("The Anthropic API key on this server isn't valid.");
      if (error instanceof Anthropic.APIError) throw new Error(`Claude returned an error (${error.status}).`);
      throw error;
    }
  }
  const { message, usage } = await compatible(model.provider, {
    model: model.id,
    temperature: 0.1,
    ...(model.id.startsWith("openai/gpt-oss") ? { reasoning_effort: "low" } : {}),
    ...(json ? { response_format: { type: "json_object" } } : {}),
    messages: [{ role: "system", content: system }, { role: "user", content: user }],
  });
  const inputTokens = usage.prompt_tokens ?? 0, outputTokens = usage.completion_tokens ?? 0;
  return { text: String(message.content ?? ""), inputTokens, outputTokens, usd: cost(model, inputTokens, outputTokens) };
}
