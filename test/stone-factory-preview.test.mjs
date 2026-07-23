import { describe, it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { StoneFactory } from "../bin/whet.js";
import { createTestProject } from "./helpers/test-env.mjs";
import { MockStone } from "./helpers/mock-stone.mjs";

let env;
afterEach(async () => {
  if (env) await env.cleanup();
  env = null;
});

// A factory whose entries each own one MockStone. `hashKey` mirrors `content`,
// so a config change moves the stone's hash and forces regeneration on getSource.
class PreviewFactory extends StoneFactory {
  constructor() {
    super();
    this.createCount = 0;
    this.updateCount = 0;
  }
  createEntry(key, data) {
    this.createCount++;
    const stone = new MockStone({
      project: this.project,
      id: `pf:${key}`,
      outputs: [{ id: `${key}.txt`, content: data.content }],
      hashKey: data.content,
    });
    return {
      stones: [stone],
      routes: [[`${key}.txt`, stone]],
      stone,
    };
  }
  updateEntry(key, data, existing) {
    this.updateCount++;
    existing.stone.config.outputs = [{ id: `${key}.txt`, content: data.content }];
    existing.stone.config.hashKey = data.content;
  }
}

it("preview changes served output; revert restores canonical", async () => {
  env = await createTestProject("preview-served");
  const factory = new PreviewFactory();
  factory.sync([{ name: "a", content: "canon" }], (d) => d.name);
  assert.equal(await factory.getString("a.txt"), "canon");

  factory.previewEntry("a", { content: "preview" });
  assert.equal(factory.isPreviewDirty("a"), true);
  assert.equal(factory.isPreviewDirty(), true);
  assert.equal(await factory.getString("a.txt"), "preview");

  assert.equal(factory.revertEntry("a"), true);
  assert.equal(factory.isPreviewDirty("a"), false);
  assert.equal(factory.isPreviewDirty(), false);
  assert.equal(await factory.getString("a.txt"), "canon");
});

it("preview of unknown key creates entry + routes; revert removes it", async () => {
  env = await createTestProject("preview-unknown");
  const factory = new PreviewFactory();
  factory.sync([{ name: "a", content: "a" }], (d) => d.name);

  // Preview a not-yet-synced key.
  factory.previewEntry("new", { content: "fresh" });
  assert.ok(factory.entryMap.has("new"));
  assert.ok(!factory.dataMap.has("new")); // canonical untouched
  assert.equal(factory.isPreviewDirty("new"), true);
  let results = await factory.get();
  assert.ok(results.some((r) => r.serveId === "new.txt"));
  assert.equal(await factory.getString("new.txt"), "fresh");

  // Revert removes the entry and its route.
  assert.equal(factory.revertEntry("new"), true);
  assert.ok(!factory.entryMap.has("new"));
  assert.equal(factory.isPreviewDirty("new"), false);
  results = await factory.get();
  assert.ok(!results.some((r) => r.serveId === "new.txt"));
  // Original route survives the rebuild.
  assert.ok(results.some((r) => r.serveId === "a.txt"));
});

it("revertEntry returns false for unknown, unpreviewed key", async () => {
  env = await createTestProject("preview-revert-false");
  const factory = new PreviewFactory();
  factory.sync([{ name: "a", content: "a" }], (d) => d.name);
  assert.equal(factory.revertEntry("nope"), false);
});

it("sync after preview reasserts canonical even when data JSON-equals dataMap", async () => {
  env = await createTestProject("preview-sync-reassert");
  const factory = new PreviewFactory();
  const canon = [{ name: "a", content: "canon" }];
  factory.sync(canon, (d) => d.name);

  factory.previewEntry("a", { content: "preview" });
  assert.equal(await factory.getString("a.txt"), "preview");

  const updatesBefore = factory.updateCount;
  // Same data as dataMap (JSON-equal) — but previewedKeys must force an update.
  factory.sync([{ name: "a", content: "canon" }], (d) => d.name);
  assert.equal(factory.updateCount, updatesBefore + 1);
  assert.equal(factory.isPreviewDirty(), false);
  assert.equal(await factory.getString("a.txt"), "canon");
});

it("skip-unchanged: updateEntry not called for JSON-equal non-previewed key", async () => {
  env = await createTestProject("preview-skip");
  const factory = new PreviewFactory();
  factory.sync([{ name: "a", content: "v1" }], (d) => d.name);
  assert.equal(factory.createCount, 1);
  assert.equal(factory.updateCount, 0);

  // Identical data — should skip updateEntry.
  factory.sync([{ name: "a", content: "v1" }], (d) => d.name);
  assert.equal(factory.updateCount, 0);

  // Changed data — should update.
  factory.sync([{ name: "a", content: "v2" }], (d) => d.name);
  assert.equal(factory.updateCount, 1);
  assert.equal(await factory.getString("a.txt"), "v2");
});

it("removed keys are dropped from dataMap/previewedKeys; sync return unchanged", async () => {
  env = await createTestProject("preview-removed");
  const factory = new PreviewFactory();
  factory.sync(
    [
      { name: "a", content: "x" },
      { name: "b", content: "y" },
    ],
    (d) => d.name,
  );
  assert.ok(factory.dataMap.has("a"));

  // Preview "a" so it's in previewedKeys, then drop it via sync.
  factory.previewEntry("a", { content: "z" });
  assert.equal(factory.isPreviewDirty("a"), true);

  const removed = factory.sync([{ name: "b", content: "y" }], (d) => d.name);
  assert.deepEqual(removed, ["a"]);
  assert.ok(!factory.dataMap.has("a"));
  assert.ok(!factory.entryMap.has("a"));
  assert.equal(factory.isPreviewDirty("a"), false);
  assert.equal(factory.isPreviewDirty(), false);
});

it("revertAllPreviews reverts every previewed key", async () => {
  env = await createTestProject("preview-revert-all");
  const factory = new PreviewFactory();
  factory.sync(
    [
      { name: "a", content: "a0" },
      { name: "b", content: "b0" },
    ],
    (d) => d.name,
  );

  factory.previewEntry("a", { content: "a1" });
  factory.previewEntry("b", { content: "b1" });
  factory.previewEntry("new", { content: "n1" }); // preview-created
  assert.equal(await factory.getString("a.txt"), "a1");

  factory.revertAllPreviews();
  assert.equal(factory.isPreviewDirty(), false);
  assert.equal(await factory.getString("a.txt"), "a0");
  assert.equal(await factory.getString("b.txt"), "b0");
  assert.ok(!factory.entryMap.has("new")); // preview-created key removed
});
