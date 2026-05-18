import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const treeItemSource = readFileSync(
  new URL("../../apps/desktop/src/components/sidebar/TreeItem.vue", import.meta.url),
  "utf8",
);

test("connection group rename input keeps the normal sidebar text size", () => {
  const inputMatch = treeItemSource.match(/<input\s+[\s\S]*?ref="renameInputRef"[\s\S]*?class="([^"]+)"/);

  assert.ok(inputMatch, "expected connection group rename input to have a class attribute");
  assert.ok(!inputMatch[1].split(/\s+/).includes("text-xs"), "rename input should not be smaller than the row label");
});
