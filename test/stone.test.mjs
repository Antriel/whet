import test from "node:test";
import assert from "node:assert/strict";

import { CacheStrategy, CacheDurability } from "../bin/whet/cache/Cache.js";
import { SourceData } from "../bin/whet/Source.js";
import { MockStone } from "./helpers/mock-stone.mjs";
import { createTestProject } from "./helpers/test-env.mjs";

test("Stone JS subclass generates source", async () => {
  const env = await createTestProject("stone-generate");
  const stone = new MockStone({ project: env.project });
  const source = await stone.getSource();
  assert.equal(source.get().data.toString("utf-8"), "out");
  assert.equal(stone.generateCount, 1);
  await env.cleanup();
});

test("Stone hash includes dependency hashes", async () => {
  const env = await createTestProject("stone-deps-hash");
  const dep = new MockStone({
    project: env.project,
    id: "dep",
    outputs: [{ id: "dep.txt", content: "dep" }],
    hashKey: "dep-v1",
  });
  const main = new MockStone({
    project: env.project,
    id: "main",
    dependencies: dep,
    hashKey: "main-v1",
  });

  const h1 = (await main.getHash()).toString();
  dep.setHashKey("dep-v2");
  const h2 = (await main.getHash()).toString();

  assert.notEqual(h1, h2);
  await env.cleanup();
});

test("setAbsolutePath(false) switches strategy without generating", async () => {
  const env = await createTestProject("stone-set-absolute-no-gen");
  const stone = new MockStone({ project: env.project, id: "abs-no-gen" });
  await stone.setAbsolutePath("fixed/out.txt", false);
  assert.equal(stone.generateCount, 0);
  await env.cleanup();
});

test("setAbsolutePath(true) writes fixed output path", async () => {
  const env = await createTestProject("stone-set-absolute-gen");
  const stone = new MockStone({
    project: env.project,
    id: "abs-gen",
    outputs: [{ id: "ignored.txt", content: "fixed-content" }],
  });
  await stone.setAbsolutePath("fixed/out.txt", true);
  assert.equal(await env.read("fixed/out.txt"), "fixed-content");
  await env.cleanup();
});

test("exportTo supports file for single output and dir for multiple output", async () => {
  const env = await createTestProject("stone-export");
  const single = new MockStone({
    project: env.project,
    id: "single",
    outputs: [{ id: "single.txt", content: "single" }],
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  await single.exportTo("exports/single.txt");
  assert.equal(await env.read("exports/single.txt"), "single");

  const multi = new MockStone({
    project: env.project,
    id: "multi",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b/b.txt", content: "B" },
    ],
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  await multi.exportTo("exports/multi/");
  assert.equal(await env.read("exports/multi/a.txt"), "A");
  assert.equal(await env.read("exports/multi/b/b.txt"), "B");

  await assert.rejects(() => multi.exportTo("exports/not-a-dir.txt"));
  await env.cleanup();
});

test("Stone handleError fallback returns source data", async () => {
  const env = await createTestProject("stone-handle-error");
  const stone = new MockStone({
    project: env.project,
    id: "handle-error",
    outputs: () => {
      throw new Error("boom");
    },
  });
  stone.handleError = async () => [
    SourceData.fromString("fallback.txt", "fallback"),
  ];

  const source = await stone.getSource();
  assert.equal(source.get().data.toString("utf-8"), "fallback");
  await env.cleanup();
});

test("Duplicate explicit Stone IDs are preserved (not deduped)", async () => {
  const env = await createTestProject("stone-dedup-explicit");
  const a = new MockStone({ project: env.project, id: "shared" });
  const b = new MockStone({ project: env.project, id: "shared" });

  // Explicit IDs are kept as-is (a warning is logged)
  assert.equal(a.id, "shared");
  assert.equal(b.id, "shared");
  await env.cleanup();
});

test("Stones with different IDs are not affected by dedup", async () => {
  const env = await createTestProject("stone-no-dedup");
  const a = new MockStone({ project: env.project, id: "alpha" });
  const b = new MockStone({ project: env.project, id: "beta" });

  assert.equal(a.id, "alpha");
  assert.equal(b.id, "beta");
  await env.cleanup();
});

test("Stone with colon in ID can use file cache without path issues", async () => {
  const env = await createTestProject("stone-colon-id");
  const stone = new MockStone({
    project: env.project,
    id: "MyStone:2",
    outputs: [{ id: "out.txt", content: "hello" }],
    cacheStrategy: CacheStrategy.InFile(CacheDurability.KeepForever, null),
  });

  // Should not throw despite colon in ID
  const source = await stone.getSource();
  assert.equal(source.get().data.toString("utf-8"), "hello");
  await env.cleanup();
});

test("Stone with arbitrary special chars in ID can use file cache", async () => {
  const env = await createTestProject("stone-special-id");
  const stone = new MockStone({
    project: env.project,
    id: "my/stone?id=1&v=2",
    outputs: [{ id: "out.txt", content: "world" }],
    cacheStrategy: CacheStrategy.InFile(CacheDurability.KeepForever, null),
  });

  const source = await stone.getSource();
  assert.equal(source.get().data.toString("utf-8"), "world");
  await env.cleanup();
});
