import test from "node:test";
import assert from "node:assert/strict";

import { Stone } from "../bin/whet.js";
import { CacheStrategy, CacheDurability, DurabilityCheck } from "../bin/whet/cache/Cache.js";
import { SourceData } from "../bin/whet/Source.js";
import { SourceHash } from "../bin/whet/SourceHash.js";
import { createTestProject } from "./helpers/test-env.mjs";

/**
 * A Stone exercising generateContext()/getContext():
 * - generateContext builds a by-reference object (a Map) and bumps contextGenerateCount.
 * - list() reads the context via the no-arg getContext() form.
 * - generatePartial() reads it via getContext(hash); output content embeds ctx.token so
 *   staleness is detectable.
 *
 * hashKey === null => no generateHash() (null hash path).
 */
class ContextStone extends Stone {
  constructor(opts = {}) {
    super({
      project: opts.project,
      id: opts.id ?? "ctx-stone",
      cacheStrategy: opts.cacheStrategy ?? CacheStrategy.None,
    });
    this._ids = opts.ids ?? ["a.txt", "b.txt", "c.txt"];
    // Distinguish "not provided" (default "v1") from explicit null (no generateHash).
    this._hashKey = "hashKey" in opts ? opts.hashKey : "v1";
    this.token = opts.token ?? "T";
    this.contextGenerateCount = 0;
    this.partialGenerateCount = 0;
  }

  async generateHash() {
    if (this._hashKey === null) return null;
    return SourceHash.fromString(String(this._hashKey));
  }

  async generateContext(hash) {
    this.contextGenerateCount += 1;
    const byId = new Map(this._ids.map((id) => [id, `${id}@${this.token}`]));
    return { token: this.token, ids: [...this._ids], byId };
  }

  async list() {
    const ctx = await this.getContext(); // no-arg form, derives hash internally
    return ctx.ids;
  }

  async generatePartial(sourceId, hash) {
    this.partialGenerateCount += 1;
    const ctx = await this.getContext(hash);
    const content = ctx.byId.get(sourceId);
    if (content == null) return null;
    return [SourceData.fromString(sourceId, content)];
  }
}

// ---------------------------------------------------------------------------
// Computed once across a generation batch
// ---------------------------------------------------------------------------

test("context computed once across N generatePartial calls in a batch (stable hash)", async () => {
  const env = await createTestProject("ctx-batch");
  const stone = new ContextStone({
    project: env.project,
    id: "ctx-batch",
    ids: ["a.txt", "b.txt", "c.txt"],
    hashKey: "v1",
    cacheStrategy: CacheStrategy.None,
  });

  const source = await stone.getSource();
  assert.equal(source.data.length, 3);
  assert.equal(source.get("a.txt").data.toString("utf-8"), "a.txt@T");
  // list() + 3 generatePartial() all shared one context.
  assert.equal(stone.contextGenerateCount, 1);
  assert.equal(stone.partialGenerateCount, 3);
  await env.cleanup();
});

test("context computed once across N generatePartial calls in a batch (null hash)", async () => {
  const env = await createTestProject("ctx-batch-null");
  const stone = new ContextStone({
    project: env.project,
    id: "ctx-batch-null",
    ids: ["a.txt", "b.txt"],
    hashKey: null, // null hash -> per-request MemoContext scoping
    cacheStrategy: CacheStrategy.None,
  });

  const source = await stone.getSource();
  assert.equal(source.data.length, 2);
  assert.equal(source.get("b.txt").data.toString("utf-8"), "b.txt@T");
  // Shared across list() + both generatePartial() within the one getSource() request.
  assert.equal(stone.contextGenerateCount, 1);
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// Reuse across separate getPartialSource calls (instance cache, stable hash)
// ---------------------------------------------------------------------------

test("context reused across separate getPartialSource calls with same hash", async () => {
  const env = await createTestProject("ctx-reuse");
  const stone = new ContextStone({
    project: env.project,
    id: "ctx-reuse",
    ids: ["a.txt", "b.txt", "c.txt"],
    hashKey: "v1",
    cacheStrategy: CacheStrategy.None, // force generatePartial each time
  });

  const a = await stone.getPartialSource("a.txt");
  const b = await stone.getPartialSource("b.txt");
  const c = await stone.getPartialSource("c.txt");
  assert.equal(a.get().data.toString("utf-8"), "a.txt@T");
  assert.equal(b.get().data.toString("utf-8"), "b.txt@T");
  assert.equal(c.get().data.toString("utf-8"), "c.txt@T");
  assert.equal(stone.partialGenerateCount, 3);
  // Each getPartialSource is its own request; the instance cache (keyed by stable hash)
  // bridges them so generateContext ran exactly once.
  assert.equal(stone.contextGenerateCount, 1);
  await env.cleanup();
});

test("concurrent getPartialSource calls share a single in-flight context", async () => {
  const env = await createTestProject("ctx-concurrent");
  const stone = new ContextStone({
    project: env.project,
    id: "ctx-concurrent",
    ids: ["a.txt", "b.txt", "c.txt"],
    hashKey: "v1",
    cacheStrategy: CacheStrategy.None,
  });

  const [a, b, c] = await Promise.all([
    stone.getPartialSource("a.txt"),
    stone.getPartialSource("b.txt"),
    stone.getPartialSource("c.txt"),
  ]);
  assert.equal(a.get().data.toString("utf-8"), "a.txt@T");
  assert.equal(b.get().data.toString("utf-8"), "b.txt@T");
  assert.equal(c.get().data.toString("utf-8"), "c.txt@T");
  // Promise (not value) is cached, so the race does not start duplicate computations.
  assert.equal(stone.contextGenerateCount, 1);
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// Recomputed on hash change
// ---------------------------------------------------------------------------

test("context recomputed when hash changes", async () => {
  const env = await createTestProject("ctx-rehash");
  const stone = new ContextStone({
    project: env.project,
    id: "ctx-rehash",
    ids: ["a.txt"],
    hashKey: "v1",
    token: "A",
    cacheStrategy: CacheStrategy.None,
  });

  const s1 = await stone.getSource();
  assert.equal(s1.get("a.txt").data.toString("utf-8"), "a.txt@A");
  assert.equal(stone.contextGenerateCount, 1);

  // Same hash again -> instance cache hit, no recompute.
  await stone.getSource();
  assert.equal(stone.contextGenerateCount, 1);

  // Change inputs (hash + token) -> recompute, fresh content.
  stone._hashKey = "v2";
  stone.token = "B";
  const s2 = await stone.getSource();
  assert.equal(s2.get("a.txt").data.toString("utf-8"), "a.txt@B");
  assert.equal(stone.contextGenerateCount, 2);
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// Null hash must NOT hold stale context across builds (regression)
// ---------------------------------------------------------------------------

test("null-hash context is not held stale across separate getSource() requests", async () => {
  const env = await createTestProject("ctx-null-stale");
  const stone = new ContextStone({
    project: env.project,
    id: "ctx-null-stale",
    ids: ["a.txt"],
    hashKey: null, // no stable key
    token: "A",
    cacheStrategy: CacheStrategy.None,
  });

  const s1 = await stone.getSource();
  assert.equal(s1.get("a.txt").data.toString("utf-8"), "a.txt@A");
  assert.equal(stone.contextGenerateCount, 1);

  // Inputs change but there is no hash to key on. A separate request must recompute,
  // not return the instance-cached stale context.
  stone.token = "B";
  const s2 = await stone.getSource();
  assert.equal(s2.get("a.txt").data.toString("utf-8"), "a.txt@B");
  assert.equal(stone.contextGenerateCount, 2);
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// Default generateContext returns null
// ---------------------------------------------------------------------------

test("default getContext returns null when generateContext is not overridden", async () => {
  const env = await createTestProject("ctx-default");
  class PlainStone extends Stone {
    constructor(opts) {
      super({ project: opts.project, id: opts.id, cacheStrategy: CacheStrategy.None });
      this.observed = "unset";
    }
    async generateHash() {
      return SourceHash.fromString("v1");
    }
    async generate() {
      this.observed = await this.getContext();
      return [SourceData.fromString("x.txt", "X")];
    }
  }
  const stone = new PlainStone({ project: env.project, id: "ctx-default" });
  const source = await stone.getSource();
  assert.equal(source.get("x.txt").data.toString("utf-8"), "X");
  assert.equal(stone.observed, null);
  await env.cleanup();
});
