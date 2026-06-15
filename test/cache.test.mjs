import test from "node:test";
import assert from "node:assert/strict";
import { Files, Project } from "../bin/whet.js";
import {
  CacheStrategy,
  CacheDurability,
  DurabilityCheck,
} from "../bin/whet/cache/Cache.js";
import { SourceData } from "../bin/whet/Source.js";
import { MockStone } from "./helpers/mock-stone.mjs";
import { createTestProject } from "./helpers/test-env.mjs";

test("CacheStrategy.None regenerates every getSource", async () => {
  const env = await createTestProject("cache-none");
  const stone = new MockStone({
    project: env.project,
    id: "none",
    hashKey: "same",
    cacheStrategy: CacheStrategy.None,
    outputs: [{ id: "x.txt", content: (n) => `v${n}` }],
  });

  await stone.getSource();
  await stone.getSource();
  assert.equal(stone.generateCount, 2);
  await env.cleanup();
});

test("InMemory KeepForever reuses cached generation when hash is stable", async () => {
  const env = await createTestProject("cache-memory-keep");
  const stone = new MockStone({
    project: env.project,
    id: "mem-keep",
    hashKey: "stable",
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, DurabilityCheck.AllOnUse),
  });

  await stone.getSource();
  await stone.getSource();
  assert.equal(stone.generateCount, 1);
  await env.cleanup();
});

test("InMemory LimitCountByLastUse(1) evicts older hash entries", async () => {
  const env = await createTestProject("cache-memory-lru1");
  const stone = new MockStone({
    project: env.project,
    id: "mem-lru",
    hashKey: "v1",
    cacheStrategy: CacheStrategy.InMemory(
      CacheDurability.LimitCountByLastUse(1),
      DurabilityCheck.AllOnUse,
    ),
    outputs: [{ id: "x.txt", content: "one" }],
  });

  await stone.getSource(); // generate v1
  stone.setHashKey("v2").setOutputs([{ id: "x.txt", content: "two" }]);
  await stone.getSource(); // generate v2, evict v1 by policy
  stone.setHashKey("v1").setOutputs([{ id: "x.txt", content: "one" }]);
  await stone.getSource(); // must regenerate v1

  assert.equal(stone.generateCount, 3);
  await env.cleanup();
});

test("File cache is reused by a new project at same root", async () => {
  const env = await createTestProject("cache-file-reuse");
  const strategy = CacheStrategy.InFile(CacheDurability.KeepForever, DurabilityCheck.AllOnUse);
  const first = new MockStone({
    project: env.project,
    id: "file-reuse",
    hashKey: "same",
    cacheStrategy: strategy,
    outputs: [{ id: "payload.txt", content: "file-cache" }],
  });

  await first.getSource();
  assert.equal(first.generateCount, 1);
  await env.project.cache.close();

  const secondProject = new Project({
    name: "whet-cache-reuse-second",
    id: "whet-cache-reuse-second",
    rootDir: env.rootDir,
  });
  const second = new MockStone({
    project: secondProject,
    id: "file-reuse",
    hashKey: "same",
    cacheStrategy: strategy,
    outputs: [{ id: "payload.txt", content: "ignored-if-cached" }],
  });
  const src = await second.getSource();

  assert.equal(second.generateCount, 0);
  assert.equal(src.get().data.toString("utf-8"), "file-cache");
  await env.cleanup();
});

test("Files stone cache updates after source file content changes", async () => {
  const env = await createTestProject("cache-files-change");
  await env.write("assets/a.txt", "A1");
  const files = new Files({
    project: env.project,
    paths: "assets/a.txt",
    cacheStrategy: CacheStrategy.InFile(CacheDurability.KeepForever, DurabilityCheck.AllOnUse),
  });

  const s1 = await files.getSource();
  const t1 = s1.get().data.toString("utf-8");
  await env.write("assets/a.txt", "A2");
  const s2 = await files.getSource();
  const t2 = s2.get().data.toString("utf-8");

  assert.equal(t1, "A1");
  assert.equal(t2, "A2");
  assert.notEqual(s1.hash.toString(), s2.hash.toString());
  await env.cleanup();
});

// PERFORMANCE_REVIEW §2.3: serving one static file from a Files directory must read only that
// file, not the whole directory.
test("Files.generatePartial reads only the requested file, not the whole directory", async () => {
  const env = await createTestProject("files-partial-read");
  await env.write("assets/a.txt", "A");
  await env.write("assets/b.txt", "B");
  await env.write("assets/c.txt", "C");
  // Default project strategy is None — the case plain file routes hit.
  const files = new Files({
    project: env.project,
    id: "files-partial",
    paths: "assets/",
  });

  // Spy on content reads. generateHash() hashes via HashCache (not SourceData.fromFile), so this
  // counts only the bytes generatePartial/generate actually read.
  const origFrom = SourceData.fromFile;
  let reads = 0;
  SourceData.fromFile = function (...a) {
    reads += 1;
    return origFrom.apply(this, a);
  };
  try {
    const src = await files.getPartialSource("b.txt");
    assert.equal(src.get().data.toString("utf-8"), "B");
    assert.equal(reads, 1); // only b.txt, not all three
  } finally {
    SourceData.fromFile = origFrom;
  }
  await env.cleanup();
});

test("refreshSource forces regeneration even with stable hash", async () => {
  const env = await createTestProject("cache-refresh");
  const stone = new MockStone({
    project: env.project,
    id: "refreshable",
    hashKey: "stable",
    outputs: [{ id: "x.txt", content: (n) => `v${n}` }],
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, DurabilityCheck.AllOnUse),
  });

  await stone.getSource();
  await env.project.cache.refreshSource(stone);
  await stone.getSource();
  assert.equal(stone.generateCount, 2);
  await env.cleanup();
});
