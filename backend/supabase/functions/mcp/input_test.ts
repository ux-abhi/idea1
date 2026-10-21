// © Pexilim
import { handle, localToUTC, parseCall } from "./input.ts";

Deno.test("tool calls are checked: known tools, a title, a local date", () => {
  const task = parseCall("add_task", { title: "  Send\n invoice ", due: "2026-10-23T15:00" });
  if (typeof task === "string" || task.tool !== "add_task" || task.title !== "Send invoice") throw new Error(JSON.stringify(task));
  if (typeof parseCall("add_task", { title: "" }) !== "string") throw new Error("empty title");
  if (typeof parseCall("add_task", { title: "x", due: "next week" }) !== "string") throw new Error("bad date");
  if (typeof parseCall("send_mail", {}) !== "string") throw new Error("unknown tool");
  if (typeof parseCall("delete_everything", {}) !== "string") throw new Error("unknown tool");
});

Deno.test("the MCP handshake, tool list, notifications and errors", async () => {
  const init = await handle({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-03-26" } }, async () => "");
  if ((init as any).result.protocolVersion !== "2025-03-26") throw new Error("keeps a version it supports");
  const list = await handle({ jsonrpc: "2.0", id: 2, method: "tools/list" }, async () => "");
  if ((list as any).result.tools.length !== 5) throw new Error("five tools");
  if (await handle({ jsonrpc: "2.0", method: "notifications/initialized" }, async () => "") !== null) throw new Error("no reply to a notification");
  const called = await handle({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "get_tasks", arguments: {} } }, async () => "2 tasks");
  if ((called as any).result.content[0].text !== "2 tasks") throw new Error("tool result");
  const refused = await handle({ jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "send_mail" } }, async () => "sent");
  if ((refused as any).result.isError !== true) throw new Error("unknown tool is an error, never run");
  if ((await handle({ id: 5, method: "x" }, async () => "") as any).error?.code !== -32600) throw new Error("needs jsonrpc 2.0");
});

Deno.test("local times become the right instant, across a clock change", () => {
  if (localToUTC("2026-10-23T15:00", "Europe/Berlin").toISOString() !== "2026-10-23T13:00:00.000Z") throw new Error("summer");
  if (localToUTC("2026-10-26T15:00", "Europe/Berlin").toISOString() !== "2026-10-26T14:00:00.000Z") throw new Error("winter");
  if (localToUTC("2026-10-23", "Asia/Kolkata").toISOString() !== "2026-10-23T03:30:00.000Z") throw new Error("a day is 09:00");
});
