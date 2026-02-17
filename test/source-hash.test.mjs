import test from "node:test";
import assert from "node:assert/strict";
import path from "node:path";

import { Router } from "../bin/whet.js";
import { SourceHash } from "../bin/whet/SourceHash.js";
import { MockStone } from "./helpers/mock-stone.mjs";
import { createTestProject } from "./helpers/test-env.mjs";

test("SourceHash fromString/fromHex/equals basic behavior", () => {
  const h1 = SourceHash.fromString("abc");
  const hex = h1.toString();
  const h2 = SourceHash.fromHex(hex);
  const bad = SourceHash.fromHex("abcd");

  assert.equal(SourceHash.equals(h1, h2), true);
  assert.equal(SourceHash.toHex(h1), hex);
  assert.equal(bad, null);
});

test("SourceHash merge changes with order and add matches merge pairwise", () => {
  const a = SourceHash.fromString("A");
  const b = SourceHash.fromString("B");
  const c = SourceHash.fromString("C");

  const m1 = SourceHash.merge(a, b, c).toString();
  const m2 = SourceHash.merge(c, b, a).toString();
  const pair = a.add(b).add(c).toString();

  assert.notEqual(m1, m2);
  assert.equal(m1, pair);
});

test("SourceHash fromFiles is deterministic for repeated calls with same input", async () => {
  const env = await createTestProject("source-hash-files-order");
  await env.write("assets/a.txt", "A");
  await env.write("assets/b.txt", "B");

  const dir = path.join(env.rootDir, "assets");
  const h1 = await SourceHash.fromFiles(dir);
  const h2 = await SourceHash.fromFiles(dir);
  assert.equal(h1.toString(), h2.toString());

  await env.cleanup();
});

test("SourceHash fromFiles supports filter for extension selection", async () => {
  const env = await createTestProject("source-hash-files-filter");
  await env.write("assets/a.txt", "A");
  await env.write("assets/b.json", '{"b":1}');
  const dir = path.join(env.rootDir, "assets");

  const all = await SourceHash.fromFiles(dir);
  const txtOnly = await SourceHash.fromFiles(dir, (p) => p.endsWith(".txt"));
  assert.notEqual(all.toString(), txtOnly.toString());

  await env.cleanup();
});

test("SourceHash fromConfig ignores base stone config keys", async () => {
  const env = await createTestProject("source-hash-config-ignore-base");
  const stone = new MockStone({
    project: env.project,
    id: "cfg-stone",
    hashKey: "stone-v1",
  });
  const router = new Router([stone]);

  const cfg1 = {
    project: env.project,
    id: "x",
    cacheStrategy: { x: 1 },
    dependencies: [stone],
    plain: "same",
    count: 1,
    stone,
    router,
  };
  const cfg2 = {
    ...cfg1,
    project: null,
    id: "y",
    cacheStrategy: { x: 999 },
    dependencies: [],
  };

  const h1 = await SourceHash.fromConfig(cfg1);
  const h2 = await SourceHash.fromConfig(cfg2);
  assert.equal(h1.toString(), h2.toString());

  await env.cleanup();
});

test("SourceHash fromConfig ignoreList excludes custom keys", async () => {
  const cfgA = { keep: "x", skipMe: "a" };
  const cfgB = { keep: "x", skipMe: "b" };

  const hA = await SourceHash.fromConfig(cfgA, ["skipMe"]);
  const hB = await SourceHash.fromConfig(cfgB, ["skipMe"]);
  assert.equal(hA.toString(), hB.toString());
});

test("Router.getHash is stable for equivalent routes in different insertion order", async () => {
  const env = await createTestProject("router-hash-order");
  const s1 = new MockStone({
    project: env.project,
    id: "order-s1",
    hashKey: "s1",
    outputs: [{ id: "a.txt", content: "A" }],
  });
  const s2 = new MockStone({
    project: env.project,
    id: "order-s2",
    hashKey: "s2",
    outputs: [{ id: "b.txt", content: "B" }],
  });

  const r1 = new Router([
    ["x/", s1],
    ["y/", s2],
  ]);
  const r2 = new Router([
    ["y/", s2],
    ["x/", s1],
  ]);

  const h1 = await r1.getHash();
  const h2 = await r2.getHash();
  assert.equal(h1.toString(), h2.toString());

  await env.cleanup();
});
