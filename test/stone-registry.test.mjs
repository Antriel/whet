import { it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { StoneRegistry, ConfigReviver, Router } from "../bin/whet.js";
import { createTestProject } from "./helpers/test-env.mjs";
import { MockStone } from "./helpers/mock-stone.mjs";

let env;
afterEach(async () => {
  if (env) await env.cleanup();
  env = null;
});

// --- StoneRegistry ---

it("built-ins are registered on import", () => {
  const names = StoneRegistry.list().map((e) => e.name).sort();
  assert.deepEqual(names, ["Files", "JsonStone", "RemoteFile", "Zip"]);
  assert.ok(StoneRegistry.get("Files"));
  assert.equal(StoneRegistry.get("Unknown"), null);
});

it("register: single-stone sugar builds stone with id==key and config passed through", async () => {
  env = await createTestProject("registry-sugar");
  StoneRegistry.register("Mock", MockStone);
  const entry = StoneRegistry.get("Mock");
  assert.equal(entry.name, "Mock");

  const built = entry.builder("my-key", {
    project: env.project,
    outputs: [{ id: "x.txt", content: "hi" }],
  });
  assert.equal(built.stones.length, 1);
  assert.strictEqual(built.mainStone, built.stones[0]);
  assert.equal(built.mainStone.id, "my-key");
  assert.equal(built.mainStone.config.outputs[0].content, "hi");
});

it("register: does not mutate the caller's config object", async () => {
  env = await createTestProject("registry-nomutate");
  StoneRegistry.register("Mock2", MockStone);
  const config = { project: env.project, outputs: [{ id: "y.txt", content: "c" }] };
  StoneRegistry.get("Mock2").builder("k", config);
  assert.equal(config.id, undefined); // id was set on a copy, not the original
});

it("registerBuilder: composite returns multiple stones + routes", async () => {
  env = await createTestProject("registry-composite");
  StoneRegistry.registerBuilder("Pair", (key, config) => {
    const a = new MockStone({
      project: env.project,
      id: `${key}:a`,
      outputs: [{ id: "a.txt", content: config.a }],
    });
    const b = new MockStone({
      project: env.project,
      id: `${key}:b`,
      outputs: [{ id: "b.txt", content: config.b }],
    });
    return {
      stones: [a, b],
      routes: [[`${key}/a.txt`, a], [`${key}/b.txt`, b]],
      mainStone: a,
    };
  });

  const built = StoneRegistry.get("Pair").builder("pk", { a: "aa", b: "bb" });
  assert.equal(built.stones.length, 2);
  assert.equal(built.routes.length, 2);

  const router = new Router(built.routes);
  const results = await router.get();
  const ids = results.map((r) => r.serveId).sort();
  assert.deepEqual(ids, ["pk/a.txt", "pk/b.txt"]);
});

it("duplicate registration warns and overwrites", () => {
  StoneRegistry.registerBuilder("Dup", () => ({ stones: [] }));
  const first = StoneRegistry.get("Dup");
  StoneRegistry.registerBuilder("Dup", () => ({ stones: [], mainStone: null }));
  const second = StoneRegistry.get("Dup");
  assert.notStrictEqual(first.builder, second.builder);
});

it("list() reports hasSchema", () => {
  StoneRegistry.register("WithSchema", MockStone, { type: "object" });
  StoneRegistry.register("NoSchema", MockStone);
  const map = new Map(StoneRegistry.list().map((e) => [e.name, e.hasSchema]));
  assert.equal(map.get("WithSchema"), true);
  assert.equal(map.get("NoSchema"), false);
});

// --- ConfigReviver ---

it("revive: nested $stone resolves to the live object", () => {
  const stoneA = { id: "a", marker: "STONE_A" };
  const seen = [];
  const resolve = (id) => {
    seen.push(id);
    return { id, marker: "STONE_" + id.toUpperCase() };
  };
  const input = {
    name: "outer",
    source: { $stone: "a" },
    nested: { deep: [{ $stone: "b" }] },
  };
  const out = ConfigReviver.revive(input, resolve);
  assert.deepEqual(seen, ["a", "b"]);
  assert.equal(out.source.marker, "STONE_A");
  assert.equal(out.nested.deep[0].marker, "STONE_B");
  // input untouched
  assert.deepEqual(input.source, { $stone: "a" });
});

it("revive: $router with mixed string + {$stone} yields a working Router", async () => {
  env = await createTestProject("reviver-router");
  await env.write("plain.txt", "PLAIN");
  const stone = new MockStone({
    project: env.project,
    id: "srcstone",
    outputs: [{ id: "gen.txt", content: "GEN" }],
  });
  const resolve = (id) => {
    if (id === "srcstone") return stone;
    throw new Error(`unknown ${id}`);
  };

  const input = {
    $router: [["plain.txt", "plain.txt"], ["gen.txt", { $stone: "srcstone" }]],
  };
  const router = ConfigReviver.revive(input, resolve);
  assert.ok(router instanceof Router);
  const plain = await router.getString("plain.txt");
  assert.equal(plain, "PLAIN");
  const gen = await router.getString("gen.txt");
  assert.equal(gen, "GEN");
});

it("revive: unknown $stone error contains the id", () => {
  const resolve = (id) => {
    throw new Error(`Stone not found: ${id}`);
  };
  assert.throws(
    () => ConfigReviver.revive({ src: { $stone: "ghost" } }, resolve),
    /ghost/,
  );
});

it("revive: malformed ref with extra keys throws", () => {
  const resolve = () => ({});
  assert.throws(
    () => ConfigReviver.revive({ $stone: "a", extra: 1 }, resolve),
    /Malformed reference/,
  );
  assert.throws(
    () => ConfigReviver.revive({ $router: [], other: true }, resolve),
    /Malformed reference/,
  );
});

it("collectStoneRefs: finds refs at any depth, deduped, first-appearance order", () => {
  const input = {
    a: { $stone: "one" },
    b: [1, { c: { $stone: "two" } }, { $stone: "one" }],
    r: { $router: [["x", { $stone: "three" }]] },
  };
  const refs = ConfigReviver.collectStoneRefs(input);
  assert.deepEqual(refs, ["one", "two", "three"]);
});

it("collectStoneRefs: returns empty for ref-free value", () => {
  assert.deepEqual(ConfigReviver.collectStoneRefs({ a: 1, b: ["x", null] }), []);
  assert.deepEqual(ConfigReviver.collectStoneRefs(null), []);
});
