import test from "node:test";
import assert from "node:assert/strict";
import { Minimatch } from "minimatch";

import { Router } from "../bin/whet.js";
import { CacheStrategy, CacheDurability } from "../bin/whet/cache/Cache.js";
import { MockStone } from "./helpers/mock-stone.mjs";
import { createTestProject } from "./helpers/test-env.mjs";

function lines(text) {
  return text.split("\n").filter(Boolean);
}

test("Router supports string file sources and route-under mapping", async () => {
  const env = await createTestProject("router-strings");
  await env.write("assets/a.txt", "A");
  await env.write("assets/nested/b.txt", "B");

  const router = new Router([
    ["public/", "assets/"],
    ["single.txt", "assets/a.txt"],
  ]);

  const listed = lines(await router.listContents());
  assert.deepEqual(listed, ["public/a.txt", "public/nested/b.txt", "single.txt"]);
  await env.cleanup();
});

test("Router filters and extractDirs transform serve paths", async () => {
  const env = await createTestProject("router-filter-extract");
  await env.write("src/foo/a.txt", "A");
  await env.write("src/bar/b.txt", "B");
  await env.write("src/bar/c.json", "{}");

  const router = new Router([
    ["pub/", "src/", "**/*.txt", "foo/"],
  ]);

  const listed = lines(await router.listContents());
  assert.deepEqual(listed, ["pub/a.txt", "pub/bar/b.txt"]);
  await env.cleanup();
});

test("Router supports nested composition and mutation via route()", async () => {
  const env = await createTestProject("router-nested-mutate");
  const first = new MockStone({
    project: env.project,
    id: "first",
    outputs: [{ id: "a.txt", content: "A" }],
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  const second = new MockStone({
    project: env.project,
    id: "second",
    outputs: [{ id: "b.txt", content: "B" }],
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });

  const nested = new Router([["first/", first]]);
  const root = new Router([nested]);
  root.route([["second/", second]]);

  const listed = lines(await root.listContents());
  assert.deepEqual(listed, ["first/a.txt", "second/b.txt"]);
  await env.cleanup();
});

test("Router get() accepts a Minimatch instance instead of a string", async () => {
  const env = await createTestProject("router-minimatch-instance");
  const stone = new MockStone({
    project: env.project,
    id: "mm",
    outputs: [
      { id: "dir/x.txt", content: "X" },
      { id: "dir/y.txt", content: "Y" },
    ],
  });
  const router = new Router([["public/", stone]]);

  const pattern = new Minimatch("public/**/x.txt");
  const results = await router.get(pattern);
  assert.equal(results.length, 1);
  assert.equal(results[0].serveId, "public/dir/x.txt");
  await env.cleanup();
});

test("Router get() returns expected serveId/sourceId mapping", async () => {
  const env = await createTestProject("router-get-mapping");
  const stone = new MockStone({
    project: env.project,
    id: "map",
    outputs: [
      { id: "dir/x.txt", content: "X" },
      { id: "dir/y.txt", content: "Y" },
    ],
  });
  const router = new Router([["public/", stone, "**/*.txt"]]);

  const results = await router.get("public/**/x.txt");
  assert.equal(results.length, 1);
  assert.equal(results[0].sourceId, "dir/x.txt");
  assert.equal(results[0].serveId, "public/dir/x.txt");
  assert.equal((await results[0].get()).data.toString("utf-8"), "X");
  await env.cleanup();
});

test("Router getHash includes serveId effects", async () => {
  const env = await createTestProject("router-hash-serve-id");
  const stone = new MockStone({
    project: env.project,
    id: "hash-src",
    outputs: [{ id: "base.txt", content: "same-bytes" }],
    hashKey: "same-key",
  });
  const r1 = new Router([["a.txt", stone]]);
  const r2 = new Router([["b.txt", stone]]);

  const h1 = (await r1.getHash()).toString();
  const h2 = (await r2.getHash()).toString();
  assert.notEqual(h1, h2);
  await env.cleanup();
});

test("Router saveInto clears destination when clearFirst=true", async () => {
  const env = await createTestProject("router-save-into");
  await env.write("src/a.txt", "A");
  const router = new Router([["public/", "src/"]]);

  await env.write("out/old.txt", "OLD");
  await router.saveInto("**", `${env.rootDir}out/`, true);

  assert.equal(await env.exists("out/old.txt"), false);
  assert.equal(await env.read("out/public/a.txt"), "A");
  await env.cleanup();
});
