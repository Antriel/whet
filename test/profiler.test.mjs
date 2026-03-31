import test from "node:test";
import assert from "node:assert/strict";
import { MockStone } from "./helpers/mock-stone.mjs";
import { createTestProject } from "./helpers/test-env.mjs";
import {
  CacheStrategy,
  CacheDurability,
} from "../bin/whet/cache/Cache.js";
import { SpanEventType } from "../bin/whet/profiler/Span.js";

test("profiler disabled by default: getSource works, no spans", async () => {
  const env = await createTestProject("prof-disabled");
  assert.equal(env.project.profiler, null);

  const stone = new MockStone({ project: env.project, id: "s1" });
  const src = await stone.getSource();
  assert.ok(src);
  assert.equal(stone.generateCount, 1);
  await env.cleanup();
});

test("profiler enabled: getSource records LockHeld, Hash, Generate spans", async () => {
  const env = await createTestProject("prof-spans");
  env.project.enableProfiling();

  const stone = new MockStone({ project: env.project, id: "s1" });
  await stone.getSource();

  const spans = env.project.profiler.recorder.getSpans();
  assert.ok(spans.length > 0, "should have recorded spans");

  const ops = spans.map((s) => s.operation);
  assert.ok(ops.includes("LockHeld"), "should have LockHeld span");
  assert.ok(ops.includes("Hash"), "should have Hash span");
  assert.ok(ops.includes("Generate"), "should have Generate span");
  await env.cleanup();
});

test("profiler: span parent-child relationships are correct", async () => {
  const env = await createTestProject("prof-parents");
  env.project.enableProfiling();

  const stone = new MockStone({ project: env.project, id: "s1" });
  await stone.getSource();

  const spans = env.project.profiler.recorder.getSpans();
  const lockHeld = spans.find((s) => s.operation === "LockHeld");
  const hash = spans.find((s) => s.operation === "Hash");
  const generate = spans.find((s) => s.operation === "Generate");

  assert.ok(lockHeld);
  assert.ok(hash);
  assert.ok(generate);
  // Hash and Generate should be children of LockHeld
  assert.equal(hash.parentId, lockHeld.id);
  assert.equal(generate.parentId, lockHeld.id);
  await env.cleanup();
});

test("profiler: cache hit skips Generate (InMemory cache)", async () => {
  const env = await createTestProject("prof-cache-hit");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  await stone.getSource();
  const firstCount = env.project.profiler.recorder.getSpans().length;

  await stone.getSource();
  const allSpans = env.project.profiler.recorder.getSpans();
  const secondSpans = allSpans.slice(firstCount);

  const secondOps = secondSpans.map((s) => s.operation);
  assert.ok(secondOps.includes("Hash"), "cache hit still hashes");
  assert.ok(!secondOps.includes("Generate"), "cache hit should not Generate");
  assert.equal(stone.generateCount, 1, "stone should only generate once");
  await env.cleanup();
});

test("profiler: LockWait span recorded when lock is contended", async () => {
  const env = await createTestProject("prof-lock-wait");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    delayMs: 30,
  });

  // Fire two concurrent getSource calls — second one should wait for lock
  const [src1, src2] = await Promise.all([
    stone.getSource(),
    stone.getSource(),
  ]);
  assert.ok(src1);
  assert.ok(src2);

  const spans = env.project.profiler.recorder.getSpans();
  const lockWaits = spans.filter((s) => s.operation === "LockWait");
  assert.equal(lockWaits.length, 1, "one call should have waited for the lock");
  assert.ok(lockWaits[0].duration >= 0, "LockWait should have a duration");
  await env.cleanup();
});

test("profiler: subscribe receives Start and End events", async () => {
  const env = await createTestProject("prof-subscribe");
  env.project.enableProfiling();

  const events = [];
  env.project.profiler.subscribe((event) => {
    events.push({
      type: event.type === SpanEventType.Start ? "start" : "end",
      op: event.span.operation,
    });
  });

  const stone = new MockStone({ project: env.project, id: "s1" });
  await stone.getSource();

  const starts = events.filter((e) => e.type === "start");
  const ends = events.filter((e) => e.type === "end");
  assert.ok(starts.length > 0, "should have start events");
  assert.ok(ends.length > 0, "should have end events");
  assert.equal(starts.length, ends.length, "every start should have an end");
  await env.cleanup();
});

test("profiler: spans have timing data", async () => {
  const env = await createTestProject("prof-timing");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    delayMs: 10,
  });
  await stone.getSource();

  const spans = env.project.profiler.recorder.getSpans();
  for (const span of spans) {
    assert.ok(span.startTime > 0, `${span.operation} should have startTime`);
    assert.ok(span.endTime > 0, `${span.operation} should have endTime`);
    assert.ok(span.duration >= 0, `${span.operation} should have non-negative duration`);
    assert.ok(span.endTime >= span.startTime, `${span.operation} endTime >= startTime`);
  }
  await env.cleanup();
});

test("profiler: SpanStats provides estimates on subsequent runs", async () => {
  const env = await createTestProject("prof-stats");
  env.project.enableProfiling({ maxSpans: 100 });

  // hashKey returns random value to force regeneration each time
  const stone = new MockStone({ project: env.project, id: "s1", hashKey: () => Math.random() });

  await stone.getSource();
  await stone.getSource();

  const spans = env.project.profiler.recorder.getSpans();
  const generates = spans.filter((s) => s.operation === "Generate");
  assert.equal(generates.length, 2, "should have two Generate spans");
  assert.ok(generates[1].estimatedDuration > 0, "second run should have estimated duration from first");
  await env.cleanup();
});

test("profiler: DependencyResolve span wraps dependency resolution", async () => {
  const env = await createTestProject("prof-deps");
  env.project.enableProfiling();

  const dep = new MockStone({ project: env.project, id: "dep" });
  const main = new MockStone({
    project: env.project,
    id: "main",
    dependencies: dep,
  });

  await main.getSource();

  const spans = env.project.profiler.recorder.getSpans();
  const depResolve = spans.find(
    (s) => s.operation === "DependencyResolve" && s.stone === "main",
  );
  assert.ok(depResolve, "should have DependencyResolve span for main stone");
  assert.ok(depResolve.metadata?.dependencyIds, "should have dependencyIds metadata");
  assert.deepEqual(depResolve.metadata.dependencyIds, ["dep"]);
  await env.cleanup();
});

test("profiler: ring buffer evicts old spans when maxSpans exceeded", async () => {
  const env = await createTestProject("prof-ring");
  env.project.enableProfiling({ maxSpans: 5 });

  // hashKey returns random value to force regeneration each time
  const stone = new MockStone({ project: env.project, id: "s1", hashKey: () => Math.random() });

  for (let i = 0; i < 5; i++) {
    await stone.getSource();
  }

  const spans = env.project.profiler.recorder.getSpans();
  assert.ok(spans.length <= 5, `ring buffer should cap at maxSpans, got ${spans.length}`);
  assert.ok(
    env.project.profiler.recorder.totalCount > 5,
    "totalCount should track all spans ever recorded",
  );
  await env.cleanup();
});

test("profiler: disableProfiling stops recording", async () => {
  const env = await createTestProject("prof-disable");
  env.project.enableProfiling();

  // hashKey returns random value to force regeneration each time
  const stone = new MockStone({ project: env.project, id: "s1", hashKey: () => Math.random() });
  await stone.getSource();
  const countWhileEnabled = env.project.profiler.recorder.totalCount;
  assert.ok(countWhileEnabled > 0);

  env.project.disableProfiling();
  assert.equal(env.project.profiler, null);

  await stone.getSource();
  // No profiler = no spans, no errors
  assert.equal(stone.generateCount, 2);
  await env.cleanup();
});

test("profiler: CacheWrite span recorded on cache miss (InMemory)", async () => {
  const env = await createTestProject("prof-cache-write");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  await stone.getSource();

  const spans = env.project.profiler.recorder.getSpans();
  const cacheWrite = spans.find((s) => s.operation === "CacheWrite");
  assert.ok(cacheWrite, "cache miss should produce a CacheWrite span");
  assert.equal(cacheWrite.stone, "s1");
  await env.cleanup();
});

test("profiler: all spans reference correct stone id", async () => {
  const env = await createTestProject("prof-stone-id");
  env.project.enableProfiling();

  const s1 = new MockStone({ project: env.project, id: "alpha" });
  const s2 = new MockStone({ project: env.project, id: "beta" });

  await Promise.all([s1.getSource(), s2.getSource()]);

  const spans = env.project.profiler.recorder.getSpans();
  const stoneIds = new Set(spans.map((s) => s.stone));
  assert.ok(stoneIds.has("alpha"), "should have spans for alpha");
  assert.ok(stoneIds.has("beta"), "should have spans for beta");

  for (const span of spans) {
    assert.ok(
      span.stone === "alpha" || span.stone === "beta",
      `unexpected stone id: ${span.stone}`,
    );
  }
  await env.cleanup();
});

// --- Phase 2: Export and Analysis tests ---

test("profiler: JSON export contains spans array and meta", async () => {
  const env = await createTestProject("prof-export-json");
  env.project.enableProfiling();

  const stone = new MockStone({ project: env.project, id: "s1" });
  await stone.getSource();

  const result = env.project.profiler.export("json");
  assert.ok(Array.isArray(result.spans), "should have spans array");
  assert.ok(result.spans.length > 0, "should have recorded spans");
  assert.ok(result.meta, "should have meta object");
  assert.equal(typeof result.meta.spanCount, "number");
  assert.equal(typeof result.meta.stoneCount, "number");
  assert.equal(typeof result.meta.totalGenerations, "number");
  assert.equal(typeof result.meta.cacheHitRate, "number");
  assert.equal(result.meta.stoneCount, 1);
  assert.equal(result.meta.totalGenerations, 1);
  await env.cleanup();
});

test("profiler: JSON export serializes span fields correctly", async () => {
  const env = await createTestProject("prof-export-fields");
  env.project.enableProfiling();

  const stone = new MockStone({ project: env.project, id: "s1" });
  await stone.getSource();

  const result = env.project.profiler.export("json");
  const span = result.spans[0];
  assert.equal(typeof span.id, "number");
  assert.equal(typeof span.stone, "string");
  assert.equal(typeof span.operation, "string");
  assert.equal(typeof span.startTime, "number");
  assert.equal(typeof span.endTime, "number");
  assert.equal(typeof span.duration, "number");
  assert.ok(
    span.status === "ok" || span.status.startsWith("error:"),
    "status should be serialized as string",
  );
  await env.cleanup();
});

test("profiler: Chrome Trace export has correct format", async () => {
  const env = await createTestProject("prof-export-trace");
  env.project.enableProfiling();

  const stone = new MockStone({ project: env.project, id: "s1" });
  await stone.getSource();

  const result = env.project.profiler.export("trace");
  assert.ok(
    Array.isArray(result.traceEvents),
    "should have traceEvents array",
  );
  assert.ok(result.traceEvents.length > 0, "should have trace events");

  const event = result.traceEvents.find((e) => e.ph === "X");
  assert.ok(event, "should have at least one complete event");
  assert.equal(event.cat, "whet");
  assert.equal(typeof event.ts, "number", "ts should be microseconds");
  assert.equal(typeof event.dur, "number", "dur should be microseconds");
  assert.equal(event.pid, 1);
  assert.equal(typeof event.tid, "number");
  assert.ok(event.name.length > 0, "should have a name");
  // Timestamps should be epoch microseconds (much larger than performance.now ms)
  assert.ok(event.ts > 1e12, "ts should be epoch microseconds");
  await env.cleanup();
});

test("profiler: Chrome Trace assigns different tids per stone", async () => {
  const env = await createTestProject("prof-trace-tids");
  env.project.enableProfiling();

  const s1 = new MockStone({ project: env.project, id: "alpha" });
  const s2 = new MockStone({ project: env.project, id: "beta" });
  await Promise.all([s1.getSource(), s2.getSource()]);

  const result = env.project.profiler.export("trace");
  const alphaEvents = result.traceEvents.filter((e) =>
    e.name.includes("alpha"),
  );
  const betaEvents = result.traceEvents.filter((e) =>
    e.name.includes("beta"),
  );
  assert.ok(alphaEvents.length > 0);
  assert.ok(betaEvents.length > 0);
  assert.notEqual(
    alphaEvents[0].tid,
    betaEvents[0].tid,
    "different stones should get different tids",
  );
  await env.cleanup();
});

test("profiler: getSummary aggregates byStone and byOperation", async () => {
  const env = await createTestProject("prof-summary");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    hashKey: () => Math.random(),
  });
  await stone.getSource();
  await stone.getSource();

  const summary = env.project.profiler.getSummary();
  assert.ok(summary.byStone, "should have byStone");
  assert.ok(summary.byOperation, "should have byOperation");
  assert.equal(typeof summary.cacheHitRate, "number");

  // byStone should track Generate spans
  assert.ok(summary.byStone.s1, "should have entry for s1");
  assert.equal(summary.byStone.s1.generates, 2);
  assert.ok(summary.byStone.s1.avgDuration >= 0);
  assert.ok(summary.byStone.s1.lastDuration >= 0);

  // byOperation should have all operations
  assert.ok(summary.byOperation.LockHeld, "should have LockHeld");
  assert.ok(summary.byOperation.Hash, "should have Hash");
  assert.ok(summary.byOperation.Generate, "should have Generate");
  assert.equal(summary.byOperation.Generate.count, 2);
  assert.ok(summary.byOperation.Generate.totalMs >= 0);
  await env.cleanup();
});

test("profiler: getSummary tracks cache hits", async () => {
  const env = await createTestProject("prof-summary-cache");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  // First call: cache miss (generates)
  await stone.getSource();
  // Second call: cache hit
  await stone.getSource();

  const summary = env.project.profiler.getSummary();
  // Should track that there was 1 generate and at least 1 cache-related span
  assert.ok(summary.byStone.s1, "should have entry for s1");
  assert.equal(summary.byStone.s1.generates, 1, "only one generate on cache miss");
  await env.cleanup();
});

// --- Metadata tests ---

test("profiler: Hash span has hashHex metadata (InMemory cache)", async () => {
  const env = await createTestProject("prof-meta-hash");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  await stone.getSource();

  const spans = env.project.profiler.recorder.getSpans();
  const hash = spans.find((s) => s.operation === "Hash");
  assert.ok(hash, "should have Hash span");
  assert.ok(hash.metadata, "Hash span should have metadata");
  assert.equal(typeof hash.metadata.hashHex, "string", "hashHex should be a string");
  assert.ok(hash.metadata.hashHex.length > 0, "hashHex should not be empty");
  await env.cleanup();
});

test("profiler: Generate span has outputCount and totalBytes metadata", async () => {
  const env = await createTestProject("prof-meta-generate");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    outputs: [
      { id: "a.txt", content: "hello" },
      { id: "b.txt", content: "world" },
    ],
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  await stone.getSource();

  const spans = env.project.profiler.recorder.getSpans();
  const gen = spans.find((s) => s.operation === "Generate");
  assert.ok(gen, "should have Generate span");
  assert.ok(gen.metadata, "Generate span should have metadata");
  assert.equal(gen.metadata.outputCount, 2, "should report 2 outputs");
  assert.equal(typeof gen.metadata.totalBytes, "number", "totalBytes should be a number");
  assert.ok(gen.metadata.totalBytes > 0, "totalBytes should be positive");
  await env.cleanup();
});

test("profiler: LockHeld span has cacheResult 'miss' on first access", async () => {
  const env = await createTestProject("prof-meta-miss");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  await stone.getSource();

  const spans = env.project.profiler.recorder.getSpans();
  const lockHeld = spans.find((s) => s.operation === "LockHeld");
  assert.ok(lockHeld, "should have LockHeld span");
  assert.ok(lockHeld.metadata, "LockHeld should have metadata");
  assert.equal(lockHeld.metadata.cacheResult, "miss", "first access should be a cache miss");
  await env.cleanup();
});

test("profiler: LockHeld span has cacheResult 'hit' on cached access", async () => {
  const env = await createTestProject("prof-meta-hit");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  await stone.getSource(); // miss
  const firstCount = env.project.profiler.recorder.getSpans().length;

  await stone.getSource(); // hit
  const allSpans = env.project.profiler.recorder.getSpans();
  const secondSpans = allSpans.slice(firstCount);
  const lockHeld = secondSpans.find((s) => s.operation === "LockHeld");
  assert.ok(lockHeld, "should have LockHeld span on second call");
  assert.ok(lockHeld.metadata, "LockHeld should have metadata");
  assert.equal(lockHeld.metadata.cacheResult, "hit", "second access should be a cache hit");
  await env.cleanup();
});

test("profiler: getSummary cacheHitRate reflects LockHeld cacheResult metadata", async () => {
  const env = await createTestProject("prof-meta-summary");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  await stone.getSource(); // miss
  await stone.getSource(); // hit
  await stone.getSource(); // hit

  const summary = env.project.profiler.getSummary();
  // 3 lookups: 1 miss + 2 hits = 2/3 hit rate
  assert.ok(summary.cacheHitRate > 0.6, `hit rate should be ~0.67, got ${summary.cacheHitRate}`);
  assert.ok(summary.cacheHitRate < 0.7, `hit rate should be ~0.67, got ${summary.cacheHitRate}`);
  assert.equal(summary.byStone.s1.cacheHits, 2);
  await env.cleanup();
});

test("profiler: DependencyResolve span has dependencyIds metadata", async () => {
  const env = await createTestProject("prof-meta-deps");
  env.project.enableProfiling();

  const dep1 = new MockStone({ project: env.project, id: "dep-a" });
  const dep2 = new MockStone({ project: env.project, id: "dep-b" });
  const main = new MockStone({
    project: env.project,
    id: "main",
    dependencies: [dep1, dep2],
  });
  await main.getSource();

  const spans = env.project.profiler.recorder.getSpans();
  const depResolve = spans.find(
    (s) => s.operation === "DependencyResolve" && s.stone === "main",
  );
  assert.ok(depResolve, "should have DependencyResolve span");
  assert.deepEqual(depResolve.metadata.dependencyIds, ["dep-a", "dep-b"]);
  await env.cleanup();
});

test("profiler: LockWait span has queuePosition and queueLength metadata", async () => {
  const env = await createTestProject("prof-meta-lockwait");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    delayMs: 30,
  });

  await Promise.all([stone.getSource(), stone.getSource()]);

  const spans = env.project.profiler.recorder.getSpans();
  const lockWait = spans.find((s) => s.operation === "LockWait");
  assert.ok(lockWait, "should have LockWait span");
  assert.ok(lockWait.metadata, "LockWait should have metadata");
  assert.equal(lockWait.metadata.queuePosition, 0, "first waiter at position 0");
  assert.equal(lockWait.metadata.queueLength, 1, "queue length should be 1");
  await env.cleanup();
});

test("profiler: None cacheStrategy sets metadata on Hash and Generate spans", async () => {
  // Regression: CacheManager's None path created spans but never called setSpanMeta /
  // setGenerateMeta, so Hash.metadata and Generate.metadata were always null.
  const env = await createTestProject("prof-meta-none");
  env.project.enableProfiling();

  // No cacheStrategy = None (the default) — goes through CacheManager directly, not BaseCache
  const stone = new MockStone({
    project: env.project,
    id: "s1",
    outputs: [{ id: "out.txt", content: "hello" }],
  });
  await stone.getSource();

  const spans = env.project.profiler.recorder.getSpans();
  const hash = spans.find((s) => s.operation === "Hash" && s.stone === "s1");
  const gen = spans.find((s) => s.operation === "Generate" && s.stone === "s1");

  assert.ok(hash, "should have Hash span");
  assert.ok(hash.metadata, "Hash span should have metadata (was null before fix)");
  assert.equal(typeof hash.metadata.hashHex, "string", "hashHex should be a string");
  assert.ok(hash.metadata.hashHex.length > 0, "hashHex should be non-empty");

  assert.ok(gen, "should have Generate span");
  assert.ok(gen.metadata, "Generate span should have metadata (was null before fix)");
  assert.equal(gen.metadata.outputCount, 1, "should report 1 output");
  assert.ok(gen.metadata.totalBytes > 0, "totalBytes should be positive");
  await env.cleanup();
});

test("profiler: getSpansSince delegates to recorder", async () => {
  const env = await createTestProject("prof-spans-since");
  env.project.enableProfiling();

  const stone = new MockStone({
    project: env.project,
    id: "s1",
    hashKey: () => Math.random(),
  });
  await stone.getSource();
  const allSpans = env.project.profiler.recorder.getSpans();
  const midId = allSpans[Math.floor(allSpans.length / 2)].id;

  await stone.getSource();
  const since = env.project.profiler.getSpansSince(midId);
  assert.ok(since.length > 0, "should have spans after midpoint");
  for (const span of since) {
    assert.ok(span.id > midId, `span id ${span.id} should be > ${midId}`);
  }
  await env.cleanup();
});
