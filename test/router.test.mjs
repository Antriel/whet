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

test("Router filter negation pattern excludes matching files", async () => {
  const env = await createTestProject("router-negation-filter");
  const stone = new MockStone({
    project: env.project,
    id: "negation",
    outputs: [
      { id: "wall.png", content: "W" },
      { id: "wall_inpaint.png", content: "I" },
      { id: "photo.jpg", content: "J" },
    ],
  });

  // Simple negation — excludes *_inpaint.png but passes all other extensions too.
  const r1 = new Router([["", stone, "!*_inpaint.png"]]);
  assert.deepEqual(lines(await r1.listContents()), ["photo.jpg", "wall.png"]);

  // Extglob with nonegate:true — leading ! is parsed as extglob !() rather than
  // whole-pattern negation, so the .png extension is also enforced.
  const r2 = new Router([["", stone, new Minimatch("!(*_inpaint).png", { nonegate: true })]]);
  assert.deepEqual(lines(await r2.listContents()), ["wall.png"]);

  // Same extglob as a plain string — wrap in @() so ! is no longer the leading
  // character and minimatch won't consume it as a negation prefix.
  const r3 = new Router([["", stone, "@(!(*_inpaint)).png"]]);
  assert.deepEqual(lines(await r3.listContents()), ["wall.png"]);

  await env.cleanup();
});

test("Router string source deduplicates Files stones (same path reuses stone)", async () => {
  const env = await createTestProject("router-files-dedup");
  await env.write("assets/a.txt", "A");

  const r1 = new Router("assets/a.txt");
  const stonesBefore = env.project.stones.length;
  const r2 = new Router("assets/a.txt");
  const stonesAfter = env.project.stones.length;

  // Second Router with same string should reuse the Files stone, not create a new one.
  assert.equal(stonesAfter, stonesBefore, "no new stone should be created for duplicate path");

  // Both routers should serve the same content.
  const res1 = await r1.get();
  const res2 = await r2.get();
  assert.equal((await res1[0].get()).data.toString("utf-8"), "A");
  assert.equal((await res2[0].get()).data.toString("utf-8"), "A");
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

// A sibling route that declares `patterns` in its output filter (like SoundBankStone)
// must not suppress sibling routes that only declare `extensions` (like the atlas/oxipng
// stones). Regression for the unsound flat merge in Router.getOutputFilter that combined
// with the mandatory-pattern-gate in OutputFilterMatcher.couldMatch to drop the whole
// source. See bean whet-gyqz.
test("Router.getOutputFilter: pattern-declaring sibling does not hide extension-only sibling", async () => {
  const env = await createTestProject("router-outputfilter-mixed");

  // Extension-only sibling — mirrors SharpStone/OxiPng (`{ extensions }`, no patterns).
  const atlas = new MockStone({
    project: env.project,
    id: "atlas",
    outputs: [{ id: "logo.avif", content: "AVIF" }],
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  atlas.getOutputFilter = () => ({ extensions: ["avif"] });

  // Pattern-declaring sibling — mirrors SoundBankStone (`{ extensions, patterns }`).
  const soundBank = new MockStone({
    project: env.project,
    id: "soundbank",
    outputs: [{ id: "soundbank.json", content: "{}" }],
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
  });
  soundBank.getOutputFilter = () => ({
    extensions: ["json"],
    patterns: ["soundbank.json", "soundbank.json.meta.json"],
  });

  // Nested under a mounted parent route so the parent's couldMatch check consults the
  // child router's combined output filter (this is where the source gets skipped).
  const child = new Router([atlas]);
  const parent = new Router([["assets/", child]]);

  // Baseline: the extension-only output is reachable.
  assert.equal((await parent.get("assets/logo.avif")).length, 1);

  // Adding the pattern-declaring sibling must NOT hide the unrelated .avif query.
  child.route([["soundbank.json", soundBank, "soundbank.json"]]);
  const results = await parent.get("assets/logo.avif");
  assert.equal(results.length, 1, "logo.avif should still resolve after adding soundbank route");
  assert.equal(results[0].serveId, "assets/logo.avif");

  // And the pattern-declaring sibling itself is still reachable.
  assert.equal((await parent.get("assets/soundbank.json")).length, 1);
  await env.cleanup();
});

// A file (non-dir) routeUnder renames the source output to exactly that path. When every
// sibling is such a pattern-declaring file-mount (so patterns survive the merge), the
// combined filter must advertise the actual served names, not `routeUnder/childPattern`.
// Regression for the bogus join in Router.getOutputFilter. See bean whet-gyqz.
test("Router.getOutputFilter: file-mount routes advertise their renamed serve path", async () => {
  const env = await createTestProject("router-outputfilter-file-mount");

  const mk = (id, srcName) => {
    const s = new MockStone({
      project: env.project,
      id,
      outputs: [{ id: srcName, content: id }],
      cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null),
    });
    // Declares patterns for its own source id (like SoundBankStone).
    s.getOutputFilter = () => ({ extensions: ["json"], patterns: [srcName] });
    return s;
  };

  const a = mk("a", "internal-a.json");
  const b = mk("b", "internal-b.json");

  // Both renamed to explicit output names — all siblings pattern-declaring, so the merge
  // keeps `patterns` and couldMatch enforces them.
  const child = new Router([
    ["alpha.json", a, "internal-a.json"],
    ["beta.json", b, "internal-b.json"],
  ]);
  const parent = new Router([["assets/", child]]);

  // The combined filter must reference the served names, not `alpha.json/internal-a.json`.
  const of = child.getOutputFilter();
  assert.ok(of.patterns.includes("alpha.json"), `patterns should include served name, got ${JSON.stringify(of.patterns)}`);

  const resA = await parent.get("assets/alpha.json");
  assert.equal(resA.length, 1, "alpha.json should resolve through the file-mount");
  assert.equal(resA[0].serveId, "assets/alpha.json");
  const resB = await parent.get("assets/beta.json");
  assert.equal(resB.length, 1, "beta.json should resolve through the file-mount");
  await env.cleanup();
});

// Two sibling stones sharing an extension (e.g. two PNG stones) must not null out the
// combined extensions. Regression for a dangling-else that set hasExtensionlessChild on a
// duplicate extension, which — once file-mount children stopped forcing the router
// unfiltered — dropped the whole subtree's extensions and made couldMatch skip it. whet-mine.
test("Router.getOutputFilter: duplicate extension across siblings keeps extensions", async () => {
  const env = await createTestProject("router-outputfilter-dup-ext");

  const pngA = new MockStone({ project: env.project, id: "pngA",
    outputs: [{ id: "a.png", content: "A" }],
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null) });
  pngA.getOutputFilter = () => ({ extensions: ["png"] });
  const pngB = new MockStone({ project: env.project, id: "pngB",
    outputs: [{ id: "b.png", content: "B" }],
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null) });
  pngB.getOutputFilter = () => ({ extensions: ["png"] });
  const avif = new MockStone({ project: env.project, id: "avif",
    outputs: [{ id: "logo.avif", content: "AV" }],
    cacheStrategy: CacheStrategy.InMemory(CacheDurability.KeepForever, null) });
  avif.getOutputFilter = () => ({ extensions: ["avif"] });

  const child = new Router([pngA, pngB, avif]);
  const of = child.getOutputFilter();
  assert.ok(of.extensions.includes("png"), "png must survive duplicate merge");
  assert.ok(of.extensions.includes("avif"), "avif must survive alongside duplicate png");

  // Nested under a mounted parent so the combined filter gates a couldMatch prune.
  const parent = new Router([["assets/", child]]);
  const res = await parent.get("assets/logo.avif");
  assert.equal(res.length, 1, "logo.avif must resolve despite sibling duplicate png extension");
  await env.cleanup();
});
