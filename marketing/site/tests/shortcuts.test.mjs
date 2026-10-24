// © Pexilim
// The site's shortcut list must be the app's: design/shortcuts.json, which the app's own test also checks.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

test("the shortcuts page shows the app's list", () => {
  const read = (path) => JSON.parse(readFileSync(new URL(path, import.meta.url), "utf8"));
  assert.deepEqual(read("../lib/shortcuts.json"), read("../../../design/shortcuts.json"));
});
