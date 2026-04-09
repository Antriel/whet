import { describe, it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { Router, StoneFactory } from "../bin/whet.js";
import { CacheStrategy, CacheDurability, DurabilityCheck } from "../bin/whet/cache/Cache.js";
import { createTestProject } from "./helpers/test-env.mjs";
import { MockStone } from "./helpers/mock-stone.mjs";

let env;
afterEach(async () => {
  if (env) await env.cleanup();
  env = null;
});

// --- Router.clearRoutes ---

it("Router.clearRoutes empties routes and subsequent get() returns empty", async () => {
  env = await createTestProject("clear-routes");
  await env.write("a.txt", "hello");
  const router = new Router("a.txt");
  const before = await router.get();
  assert.equal(before.length, 1);
  router.clearRoutes();
  const after = await router.get();
  assert.equal(after.length, 0);
});

it("Router.clearRoutes allows re-adding routes", async () => {
  env = await createTestProject("clear-reroute");
  await env.write("a.txt", "a");
  await env.write("b.txt", "b");
  const router = new Router("a.txt");
  router.clearRoutes();
  router.route("b.txt");
  const results = await router.get();
  assert.equal(results.length, 1);
  assert.equal(results[0].serveId, "b.txt");
});

// --- Project.removeStone ---

it("Project.removeStone removes stone from project.stones", async () => {
  env = await createTestProject("remove-stone");
  const stone = new MockStone({ project: env.project, id: "to-remove" });
  assert.ok(env.project.stones.includes(stone));
  const result = env.project.removeStone(stone);
  assert.equal(result, true);
  assert.ok(!env.project.stones.includes(stone));
});

it("Project.removeStone returns false for unknown stone", async () => {
  env = await createTestProject("remove-unknown");
  const stone = new MockStone({ project: env.project, id: "present" });
  env.project.removeStone(stone);
  // Second removal should return false
  const result = env.project.removeStone(stone);
  assert.equal(result, false);
});

it("Project.removeStone does not affect other stones", async () => {
  env = await createTestProject("remove-other");
  const a = new MockStone({ project: env.project, id: "stone-a" });
  const b = new MockStone({ project: env.project, id: "stone-b" });
  env.project.removeStone(a);
  assert.ok(env.project.stones.includes(b));
  assert.ok(!env.project.stones.includes(a));
});

// --- CacheManager.clearStone ---

it("CacheManager.clearStone removes memory cache entries", async () => {
  env = await createTestProject("clear-cache-mem");
  const stone = new MockStone({
    project: env.project,
    id: "cached",
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, DurabilityCheck.AllOnUse),
  });
  // Generate to populate cache
  await stone.getSource();
  assert.equal(stone.generateCount, 1);
  // Second call should be cached
  await stone.getSource();
  assert.equal(stone.generateCount, 1);
  // Clear cache
  env.project.cache.clearStone(stone);
  // Should regenerate
  await stone.getSource();
  assert.equal(stone.generateCount, 2);
});

// --- StoneFactory ---

class TestFactory extends StoneFactory {
  createEntry(key, data) {
    const stone = new MockStone({
      project: this.project,
      id: `factory:${key}`,
      outputs: [{ id: `${key}.txt`, content: data.content }],
      hashKey: data.content,
    });
    return {
      stones: [stone],
      routes: [[`${key}.txt`, stone]],
      stone, // extra field for updateEntry
    };
  }

  updateEntry(key, data, existing) {
    existing.stone.config.outputs = [
      { id: `${key}.txt`, content: data.content },
    ];
    existing.stone.config.hashKey = data.content;
  }
}

it("StoneFactory.sync creates entries and routes them", async () => {
  env = await createTestProject("factory-create");
  const factory = new TestFactory();
  factory.sync(
    [
      { name: "a", content: "hello" },
      { name: "b", content: "world" },
    ],
    (d) => d.name,
  );

  assert.equal(factory.entryMap.size, 2);
  const results = await factory.get();
  assert.equal(results.length, 2);
  const ids = results.map((r) => r.serveId).sort();
  assert.deepEqual(ids, ["a.txt", "b.txt"]);
});

it("StoneFactory.sync updates existing entries in-place", async () => {
  env = await createTestProject("factory-update");
  const factory = new TestFactory();
  factory.sync([{ name: "a", content: "v1" }], (d) => d.name);
  const stonesBefore = env.project.stones.length;
  factory.sync([{ name: "a", content: "v2" }], (d) => d.name);
  // Should not create new stones (updateEntry modifies in-place)
  assert.equal(env.project.stones.length, stonesBefore);
  const entry = factory.entryMap.get("a");
  assert.equal(entry.stone.config.outputs[0].content, "v2");
});

it("StoneFactory.sync removes absent entries and deregisters stones", async () => {
  env = await createTestProject("factory-remove");
  const factory = new TestFactory();
  factory.sync(
    [
      { name: "a", content: "x" },
      { name: "b", content: "y" },
    ],
    (d) => d.name,
  );
  const stoneA = factory.entryMap.get("a").stone;
  assert.ok(env.project.stones.includes(stoneA));

  const removed = factory.sync(
    [{ name: "b", content: "y" }],
    (d) => d.name,
  );
  assert.deepEqual(removed, ["a"]);
  assert.ok(!env.project.stones.includes(stoneA));
  assert.equal(factory.entryMap.size, 1);
  assert.ok(factory.entryMap.has("b"));
});

it("StoneFactory.removeEntry deregisters stones individually", async () => {
  env = await createTestProject("factory-remove-entry");
  const factory = new TestFactory();
  factory.sync([{ name: "x", content: "data" }], (d) => d.name);
  console.log(factory.entryMap.get("x"));
  const stone = factory.entryMap.get("x").stone;
  assert.ok(env.project.stones.includes(stone));

  factory.removeEntry("x");
  assert.ok(!env.project.stones.includes(stone));
  assert.equal(factory.entryMap.size, 0);
});

it("StoneFactory.addBaseRoutes is called on every sync", async () => {
  env = await createTestProject("factory-base-routes");
  let baseRoutesCalled = 0;

  class FactoryWithBase extends StoneFactory {
    createEntry(key, data) {
      const stone = new MockStone({
        project: this.project,
        id: `fb:${key}`,
        outputs: [{ id: `${key}.txt`, content: "c" }],
      });
      return { stones: [stone], routes: [[`${key}.txt`, stone]] };
    }
    addBaseRoutes() {
      baseRoutesCalled++;
    }
  }

  const factory = new FactoryWithBase();
  factory.sync([{ name: "a" }], (d) => d.name);
  assert.equal(baseRoutesCalled, 1);
  factory.sync([{ name: "a" }], (d) => d.name);
  assert.equal(baseRoutesCalled, 2);
});

it("StoneFactory default updateEntry destroys and recreates", async () => {
  env = await createTestProject("factory-default-update");

  class NoUpdateFactory extends StoneFactory {
    createEntry(key, data) {
      const stone = new MockStone({
        project: this.project,
        id: `nu:${key}`,
        outputs: [{ id: `${key}.txt`, content: data.content }],
      });
      return { stones: [stone], routes: [[`${key}.txt`, stone]] };
    }
    // No updateEntry override — uses default destroy+recreate
  }

  const factory = new NoUpdateFactory();
  factory.sync([{ name: "a", content: "v1" }], (d) => d.name);
  const oldStone = factory.entryMap.get("a").stones[0];

  factory.sync([{ name: "a", content: "v2" }], (d) => d.name);
  const newStone = factory.entryMap.get("a").stones[0];

  // Old stone should be deregistered, new one registered
  assert.notStrictEqual(oldStone, newStone);
  assert.ok(!env.project.stones.includes(oldStone));
  assert.ok(env.project.stones.includes(newStone));
});
