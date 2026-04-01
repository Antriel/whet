import test from "node:test";
import assert from "node:assert/strict";
import { MockStone } from "./helpers/mock-stone.mjs";
import { createTestProject } from "./helpers/test-env.mjs";
import { Router } from "../bin/whet.js";
import {
  CacheStrategy,
  CacheDurability,
} from "../bin/whet/cache/Cache.js";

test("diamond dependency: shared stone generates only once", async () => {
  const env = await createTestProject("memo-diamond");
  // D is shared dependency of B and C; A depends on B and C.
  const stoneD = new MockStone({ project: env.project, id: "D", outputs: [{ id: "d.txt", content: "d" }] });
  const stoneB = new MockStone({ project: env.project, id: "B", dependencies: stoneD, outputs: [{ id: "b.txt", content: "b" }] });
  const stoneC = new MockStone({ project: env.project, id: "C", dependencies: stoneD, outputs: [{ id: "c.txt", content: "c" }] });
  const stoneA = new MockStone({ project: env.project, id: "A", dependencies: [stoneB, stoneC], outputs: [{ id: "a.txt", content: "a" }] });

  await stoneA.getSource();

  // D should have been generated only once due to memo context.
  assert.equal(stoneD.generateCount, 1, "D should generate exactly once");
  assert.equal(stoneB.generateCount, 1);
  assert.equal(stoneC.generateCount, 1);
  assert.equal(stoneA.generateCount, 1);
  await env.cleanup();
});

test("separate top-level calls create independent contexts", async () => {
  const env = await createTestProject("memo-independent");
  const stone = new MockStone({
    project: env.project,
    id: "s1",
    hashKey: null, // No generateHash -> goes through full generation
    cacheStrategy: CacheStrategy.None,
    outputs: [{ id: "out.txt", content: (n) => `v${n}` }],
  });

  await stone.getSource();
  await stone.getSource();

  // With CacheStrategy.None and no hash, each top-level call should regenerate.
  assert.equal(stone.generateCount, 2, "separate top-level calls should not share memo");
  await env.cleanup();
});

test("getHash memo: diamond dependency hashes shared stone only once", async () => {
  const env = await createTestProject("memo-hash-diamond");
  // D is shared dependency — its hash should be computed once within A's call tree.
  const stoneD = new MockStone({ project: env.project, id: "D" });
  const stoneB = new MockStone({ project: env.project, id: "B", dependencies: stoneD });
  const stoneC = new MockStone({ project: env.project, id: "C", dependencies: stoneD });
  const stoneA = new MockStone({ project: env.project, id: "A", dependencies: [stoneB, stoneC] });

  const hash = await stoneA.getHash();
  assert.ok(hash);
  // With generateHash implemented, no generation needed — hash is computed directly.
  // The memo dedup means D's getHash() promise is shared across B and C's finalizeHash.
  assert.equal(stoneD.generateCount, 0, "D should not generate when hash is available");
  await env.cleanup();
});

test("getPartialSource without hash falls through to memoized getSource", async () => {
  const env = await createTestProject("memo-partial");
  const stone = new MockStone({
    project: env.project,
    id: "multi",
    hashKey: null, // No hash -> getPartialSource falls through to getSource
    outputs: [
      { id: "a.txt", content: "aaa" },
      { id: "b.txt", content: "bbb" },
    ],
  });

  // getPartialSource with no hash calls getSource + filter.
  // Within that call tree, getSource is memoized.
  const p1 = await stone.getPartialSource("a.txt");
  assert.ok(p1);
  assert.equal(p1.get().data.toString("utf-8"), "aaa");
  assert.equal(stone.generateCount, 1);
  await env.cleanup();
});

test("memo works through Router: stones within get() share context", async () => {
  const env = await createTestProject("memo-router");
  // Two routes pointing to same stone — listIds is called once within Router.get().
  const stone = new MockStone({
    project: env.project,
    id: "rs",
    outputs: [
      { id: "x.txt", content: "xx" },
      { id: "y.txt", content: "yy" },
    ],
  });

  const router = new Router([["pub/", stone]]);
  const results = await router.get();
  assert.equal(results.length, 2);
  // Stone should have generated only once for both routes within Router.get().
  assert.equal(stone.generateCount, 1);
  await env.cleanup();
});

test("Router.getHash with diamond: shared dep hashed once", async () => {
  const env = await createTestProject("memo-router-hash");
  const shared = new MockStone({ project: env.project, id: "shared" });
  const a = new MockStone({ project: env.project, id: "a", dependencies: shared, outputs: [{ id: "a.txt", content: "a" }] });
  const b = new MockStone({ project: env.project, id: "b", dependencies: shared, outputs: [{ id: "b.txt", content: "b" }] });

  const router = new Router([["a/", a], ["b/", b]]);
  const hash = await router.getHash();
  assert.ok(hash);
  // shared should generate only once within the Router.getHash() context.
  assert.equal(shared.generateCount, 1, "shared dep should generate once");
  await env.cleanup();
});

test("memo works with profiling enabled", async () => {
  const env = await createTestProject("memo-profiled");
  env.project.enableProfiling();

  const stoneD = new MockStone({ project: env.project, id: "D" });
  const stoneB = new MockStone({ project: env.project, id: "B", dependencies: stoneD });
  const stoneC = new MockStone({ project: env.project, id: "C", dependencies: stoneD });
  const stoneA = new MockStone({ project: env.project, id: "A", dependencies: [stoneB, stoneC] });

  await stoneA.getSource();
  assert.equal(stoneD.generateCount, 1, "D should generate once even with profiling");
  await env.cleanup();
});

test("memo works with profiling disabled", async () => {
  const env = await createTestProject("memo-no-profiler");
  assert.equal(env.project.profiler, null);

  const stoneD = new MockStone({ project: env.project, id: "D" });
  const stoneB = new MockStone({ project: env.project, id: "B", dependencies: stoneD });
  const stoneA = new MockStone({ project: env.project, id: "A", dependencies: [stoneB] });

  await stoneA.getSource();
  assert.equal(stoneD.generateCount, 1, "D should generate once without profiling");
  await env.cleanup();
});
