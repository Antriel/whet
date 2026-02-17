import test from "node:test";
import assert from "node:assert/strict";

import {
  CacheStrategy,
  CacheDurability,
  DurabilityCheck,
} from "../bin/whet/cache/Cache.js";
import { SourceData } from "../bin/whet/Source.js";
import { SourceHash } from "../bin/whet/SourceHash.js";
import { MockStone } from "./helpers/mock-stone.mjs";
import { createTestProject } from "./helpers/test-env.mjs";

/**
 * A MockStone that supports partial generation and optional list().
 * - generatePartial: generates only the requested sourceId
 * - list: returns known output IDs without generating (if listFn is set)
 */
class PartialMockStone extends MockStone {
  constructor(opts = {}) {
    super(opts);
    this.partialGenerateCount = 0;
    this.listCallCount = 0;
    this._listFn = opts.listFn ?? null; // () => string[] | null
  }

  async generatePartial(sourceId, hash) {
    this.partialGenerateCount += 1;
    const defs =
      typeof this.config.outputs === "function"
        ? this.config.outputs(this.generateCount)
        : this.config.outputs;
    const match = defs.find((d) => d.id === sourceId);
    if (!match) return null;
    return [
      SourceData.fromString(
        match.id,
        typeof match.content === "function"
          ? String(match.content(this.partialGenerateCount))
          : String(match.content),
      ),
    ];
  }

  async list() {
    this.listCallCount += 1;
    if (this._listFn) return this._listFn();
    return null;
  }
}

// ---------------------------------------------------------------------------
// Source.filterTo
// ---------------------------------------------------------------------------

test("Source.filterTo returns matching entry", async () => {
  const env = await createTestProject("filter-to-match");
  const stone = new MockStone({
    project: env.project,
    id: "ft",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
    ],
    cacheStrategy: CacheStrategy.None,
  });

  const source = await stone.getSource();
  const filtered = source.filterTo("a.txt");
  assert.notEqual(filtered, null);
  assert.equal(filtered.data.length, 1);
  assert.equal(filtered.get().data.toString("utf-8"), "A");
  await env.cleanup();
});

test("Source.filterTo returns null for missing sourceId", async () => {
  const env = await createTestProject("filter-to-miss");
  const stone = new MockStone({
    project: env.project,
    id: "ft-miss",
    outputs: [{ id: "a.txt", content: "A" }],
    cacheStrategy: CacheStrategy.None,
  });

  const source = await stone.getSource();
  assert.equal(source.filterTo("nonexistent.txt"), null);
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// Gate check: stone without generateHash falls back to full gen + filter
// ---------------------------------------------------------------------------

test("getPartialSource without generateHash falls back to full gen + filter", async () => {
  const env = await createTestProject("partial-no-hash");
  const stone = new MockStone({
    project: env.project,
    id: "no-hash",
    hashKey: null, // no generateHash
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
    ],
    cacheStrategy: CacheStrategy.InMemory(
      CacheDurability.KeepForever,
      DurabilityCheck.AllOnUse,
    ),
  });

  const result = await stone.getPartialSource("a.txt");
  assert.notEqual(result, null);
  assert.equal(result.data.length, 1);
  assert.equal(result.get().data.toString("utf-8"), "A");
  // Full generation happened (not partial).
  assert.equal(stone.generateCount, 1);
  await env.cleanup();
});

test("getPartialSource without generateHash returns null for missing id", async () => {
  const env = await createTestProject("partial-no-hash-miss");
  const stone = new MockStone({
    project: env.project,
    id: "no-hash-miss",
    hashKey: null,
    outputs: [{ id: "a.txt", content: "A" }],
    cacheStrategy: CacheStrategy.None,
  });

  const result = await stone.getPartialSource("nonexistent.txt");
  assert.equal(result, null);
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// Partial generation fallback (no generatePartial override)
// ---------------------------------------------------------------------------

test("getPartialSource on stone without generatePartial does full gen + filter (InMemory)", async () => {
  const env = await createTestProject("partial-fallback-mem");
  const stone = new MockStone({
    project: env.project,
    id: "no-partial",
    hashKey: "stable",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
    ],
    cacheStrategy: CacheStrategy.InMemory(
      CacheDurability.KeepForever,
      DurabilityCheck.AllOnUse,
    ),
  });

  const result = await stone.getPartialSource("b.txt");
  assert.notEqual(result, null);
  assert.equal(result.get().data.toString("utf-8"), "B");
  assert.equal(stone.generateCount, 1);

  // Second request should be cached (entry is complete from full gen).
  const result2 = await stone.getPartialSource("a.txt");
  assert.notEqual(result2, null);
  assert.equal(result2.get().data.toString("utf-8"), "A");
  assert.equal(stone.generateCount, 1); // no regeneration
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// Partial generation with generatePartial override
// ---------------------------------------------------------------------------

test("getPartialSource with generatePartial generates only requested output (InMemory)", async () => {
  const env = await createTestProject("partial-gen-mem");
  const stone = new PartialMockStone({
    project: env.project,
    id: "partial",
    hashKey: "stable",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
      { id: "c.txt", content: "C" },
    ],
    cacheStrategy: CacheStrategy.InMemory(
      CacheDurability.KeepForever,
      DurabilityCheck.AllOnUse,
    ),
  });

  const result = await stone.getPartialSource("b.txt");
  assert.notEqual(result, null);
  assert.equal(result.get().data.toString("utf-8"), "B");
  assert.equal(stone.partialGenerateCount, 1);
  assert.equal(stone.generateCount, 0); // no full generation
  await env.cleanup();
});

test("getPartialSource with generatePartial returns null for missing sourceId (InMemory)", async () => {
  const env = await createTestProject("partial-gen-miss-mem");
  const stone = new PartialMockStone({
    project: env.project,
    id: "partial-miss",
    hashKey: "stable",
    outputs: [{ id: "a.txt", content: "A" }],
    cacheStrategy: CacheStrategy.InMemory(
      CacheDurability.KeepForever,
      DurabilityCheck.AllOnUse,
    ),
  });

  // Request an ID that doesn't exist in outputs.
  // generatePartial returns null for it, so it falls back to full gen.
  // Full gen doesn't have it either, so filterTo returns null.
  const result = await stone.getPartialSource("nonexistent.txt");
  assert.equal(result, null);
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// Cache sharing: partial then full, full then partial
// ---------------------------------------------------------------------------

test("partial then full: getSource completes partial entry (no list override)", async () => {
  const env = await createTestProject("partial-then-full-no-list");
  const stone = new PartialMockStone({
    project: env.project,
    id: "p-then-f",
    hashKey: "stable",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
    ],
    cacheStrategy: CacheStrategy.InMemory(
      CacheDurability.KeepForever,
      DurabilityCheck.AllOnUse,
    ),
  });

  // Partial request creates incomplete entry.
  await stone.getPartialSource("a.txt");
  assert.equal(stone.partialGenerateCount, 1);
  assert.equal(stone.generateCount, 0);

  // Full request finds partial entry, list() returns null -> full generateSource.
  const full = await stone.getSource();
  assert.equal(full.data.length, 2);
  assert.equal(stone.generateCount, 1); // full gen triggered
  await env.cleanup();
});

test("partial then full: getSource completes incrementally (with list override)", async () => {
  const env = await createTestProject("partial-then-full-list");
  const stone = new PartialMockStone({
    project: env.project,
    id: "p-then-f-list",
    hashKey: "stable",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
      { id: "c.txt", content: "C" },
    ],
    listFn: () => ["a.txt", "b.txt", "c.txt"],
    cacheStrategy: CacheStrategy.InMemory(
      CacheDurability.KeepForever,
      DurabilityCheck.AllOnUse,
    ),
  });

  // Partial request for one item.
  await stone.getPartialSource("a.txt");
  assert.equal(stone.partialGenerateCount, 1);
  assert.equal(stone.generateCount, 0);

  // Full request: list() returns all IDs, generates only missing b.txt and c.txt.
  const full = await stone.getSource();
  assert.equal(full.data.length, 3);
  assert.equal(stone.generateCount, 0); // no full gen
  // partialGenerateCount: 1 (initial a.txt) + 2 (b.txt, c.txt during completion) = 3
  assert.equal(stone.partialGenerateCount, 3);
  await env.cleanup();
});

test("full then partial: getPartialSource served from complete cache (InMemory)", async () => {
  const env = await createTestProject("full-then-partial-mem");
  const stone = new PartialMockStone({
    project: env.project,
    id: "f-then-p",
    hashKey: "stable",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
    ],
    cacheStrategy: CacheStrategy.InMemory(
      CacheDurability.KeepForever,
      DurabilityCheck.AllOnUse,
    ),
  });

  // Full gen first.
  await stone.getSource();
  assert.equal(stone.generateCount, 1);

  // Partial request served from cache — no generation.
  const result = await stone.getPartialSource("b.txt");
  assert.notEqual(result, null);
  assert.equal(result.get().data.toString("utf-8"), "B");
  assert.equal(stone.generateCount, 1);
  assert.equal(stone.partialGenerateCount, 0);
  await env.cleanup();
});

test("full then partial: returns null for nonexistent sourceId from complete entry", async () => {
  const env = await createTestProject("full-then-partial-miss");
  const stone = new PartialMockStone({
    project: env.project,
    id: "f-then-p-miss",
    hashKey: "stable",
    outputs: [{ id: "a.txt", content: "A" }],
    cacheStrategy: CacheStrategy.InMemory(
      CacheDurability.KeepForever,
      DurabilityCheck.AllOnUse,
    ),
  });

  await stone.getSource();
  const result = await stone.getPartialSource("nonexistent.txt");
  assert.equal(result, null);
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// Cache isolation: different sourceIds in same entry
// ---------------------------------------------------------------------------

test("multiple partial requests accumulate in same cache entry (InMemory)", async () => {
  const env = await createTestProject("partial-accum-mem");
  const stone = new PartialMockStone({
    project: env.project,
    id: "accum",
    hashKey: "stable",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
      { id: "c.txt", content: "C" },
    ],
    cacheStrategy: CacheStrategy.InMemory(
      CacheDurability.KeepForever,
      DurabilityCheck.AllOnUse,
    ),
  });

  const a = await stone.getPartialSource("a.txt");
  assert.equal(a.get().data.toString("utf-8"), "A");
  assert.equal(stone.partialGenerateCount, 1);

  const b = await stone.getPartialSource("b.txt");
  assert.equal(b.get().data.toString("utf-8"), "B");
  assert.equal(stone.partialGenerateCount, 2);

  // Re-request a.txt — should be served from cache, no additional generation.
  const a2 = await stone.getPartialSource("a.txt");
  assert.equal(a2.get().data.toString("utf-8"), "A");
  assert.equal(stone.partialGenerateCount, 2); // no new generation
  assert.equal(stone.generateCount, 0); // no full gen at all
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// Duplicate-id prevention (upsert, not append)
// ---------------------------------------------------------------------------

test("requesting same sourceId twice does not create duplicate in entry", async () => {
  const env = await createTestProject("partial-dedup");
  let counter = 0;
  const stone = new PartialMockStone({
    project: env.project,
    id: "dedup",
    hashKey: "stable",
    outputs: [
      { id: "a.txt", content: () => `A-${++counter}` },
      { id: "b.txt", content: "B" },
    ],
    listFn: () => ["a.txt", "b.txt"],
    cacheStrategy: CacheStrategy.InMemory(
      CacheDurability.KeepForever,
      DurabilityCheck.AllOnUse,
    ),
  });

  await stone.getPartialSource("a.txt");
  // a.txt is now in the partial entry.

  // Request a.txt again — should be served from cache (already in entry).
  await stone.getPartialSource("a.txt");
  assert.equal(stone.partialGenerateCount, 1); // only generated once

  // Now complete via getSource with list() — should not duplicate a.txt.
  const full = await stone.getSource();
  const aEntries = full.data.filter((d) => d.id === "a.txt");
  assert.equal(aEntries.length, 1, "a.txt should appear exactly once");
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// FileCache: partial generation works with file-backed cache
// ---------------------------------------------------------------------------

test("getPartialSource works with InFile cache (partial then full)", async () => {
  const env = await createTestProject("partial-file-cache");
  const strategy = CacheStrategy.InFile(
    CacheDurability.KeepForever,
    DurabilityCheck.AllOnUse,
  );
  const stone = new PartialMockStone({
    project: env.project,
    id: "file-partial",
    hashKey: "stable",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
    ],
    cacheStrategy: strategy,
  });

  // Partial request.
  const a = await stone.getPartialSource("a.txt");
  assert.notEqual(a, null);
  assert.equal(a.get().data.toString("utf-8"), "A");
  assert.equal(stone.partialGenerateCount, 1);
  assert.equal(stone.generateCount, 0);

  // Full request completes the entry.
  const full = await stone.getSource();
  assert.equal(full.data.length, 2);

  // Partial request served from now-complete cache.
  const b = await stone.getPartialSource("b.txt");
  assert.notEqual(b, null);
  assert.equal(b.get().data.toString("utf-8"), "B");
  await env.cleanup();
});

test("FileCache partial entry survives project reload", async () => {
  const env = await createTestProject("partial-file-persist");
  const strategy = CacheStrategy.InFile(
    CacheDurability.KeepForever,
    DurabilityCheck.AllOnUse,
  );

  // First project: generate partial entry.
  const stone1 = new PartialMockStone({
    project: env.project,
    id: "file-persist",
    hashKey: "stable",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
    ],
    cacheStrategy: strategy,
  });
  await stone1.getPartialSource("a.txt");
  assert.equal(stone1.partialGenerateCount, 1);
  await env.project.cache.close();

  // Second project at same root: partial entry should be loaded from disk.
  const { Project } = await import("../bin/whet.js");
  const project2 = new Project({
    name: "whet-persist-2",
    id: "whet-persist-2",
    rootDir: env.rootDir,
  });
  const stone2 = new PartialMockStone({
    project: project2,
    id: "file-persist",
    hashKey: "stable",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
    ],
    cacheStrategy: strategy,
  });

  // a.txt should be served from persisted partial cache — no generation.
  const a = await stone2.getPartialSource("a.txt");
  assert.notEqual(a, null);
  assert.equal(a.get().data.toString("utf-8"), "A");
  assert.equal(stone2.partialGenerateCount, 0);
  assert.equal(stone2.generateCount, 0);

  await project2.cache.close();
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// CacheStrategy.None: no caching for partial
// ---------------------------------------------------------------------------

test("getPartialSource with CacheStrategy.None regenerates every time", async () => {
  const env = await createTestProject("partial-no-cache");
  const stone = new PartialMockStone({
    project: env.project,
    id: "no-cache",
    hashKey: "stable",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
    ],
    cacheStrategy: CacheStrategy.None,
  });

  await stone.getPartialSource("a.txt");
  await stone.getPartialSource("a.txt");
  assert.equal(stone.partialGenerateCount, 2); // regenerated both times
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// listIds() public API
// ---------------------------------------------------------------------------

test("listIds() uses list() fast path when available", async () => {
  const env = await createTestProject("list-ids-fast");
  const stone = new PartialMockStone({
    project: env.project,
    id: "list-fast",
    hashKey: "stable",
    outputs: [
      { id: "a.txt", content: "A" },
      { id: "b.txt", content: "B" },
    ],
    listFn: () => ["a.txt", "b.txt"],
    cacheStrategy: CacheStrategy.None,
  });

  const ids = await stone.listIds();
  assert.deepEqual(ids, ["a.txt", "b.txt"]);
  assert.equal(stone.generateCount, 0); // no generation needed
  assert.equal(stone.listCallCount, 1);
  await env.cleanup();
});

test("listIds() falls back to full generation when list() returns null", async () => {
  const env = await createTestProject("list-ids-fallback");
  const stone = new MockStone({
    project: env.project,
    id: "list-fallback",
    hashKey: "stable",
    outputs: [
      { id: "x.txt", content: "X" },
      { id: "y.txt", content: "Y" },
    ],
    cacheStrategy: CacheStrategy.InMemory(
      CacheDurability.KeepForever,
      DurabilityCheck.AllOnUse,
    ),
  });

  const ids = await stone.listIds();
  assert.deepEqual(ids, ["x.txt", "y.txt"]);
  assert.equal(stone.generateCount, 1); // had to generate to get IDs
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// Source.complete field
// ---------------------------------------------------------------------------

test("Source.complete is true for full generation", async () => {
  const env = await createTestProject("complete-flag-full");
  const stone = new MockStone({
    project: env.project,
    id: "complete-full",
    outputs: [{ id: "a.txt", content: "A" }],
    cacheStrategy: CacheStrategy.None,
  });

  const source = await stone.getSource();
  assert.equal(source.complete, true);
  await env.cleanup();
});
