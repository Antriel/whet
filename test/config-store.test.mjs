import test from "node:test";
import assert from "node:assert/strict";
import { writeFile, readFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { ConfigStore, Project, Router } from "../bin/whet.js";
import { SourceHash } from "../bin/whet/SourceHash.js";
import {
  CacheStrategy,
  CacheDurability,
  DurabilityCheck,
} from "../bin/whet/cache/Cache.js";
import { MockStone } from "./helpers/mock-stone.mjs";
import { createTestProject } from "./helpers/test-env.mjs";

test("Patch application produces correct merged config (nested objects, arrays, primitives)", async () => {
  const env = await createTestProject("cs-merge");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);

  const stone = new MockStone({
    project: env.project,
    id: "merge-stone",
    configStore: store,
  });
  // Set some data fields on config (these are JSON-serializable).
  stone.config.encoding = { bitrate: 128, codec: "opus" };
  stone.config.tags = ["a", "b"];
  stone.config.volume = 0.8;

  // Write patch file.
  await writeFile(
    configPath,
    JSON.stringify({
      "merge-stone": {
        encoding: { bitrate: 256 },
        tags: ["x"],
        volume: 1.0,
      },
    }),
  );

  await stone.getHash();

  // Objects: recursive merge (bitrate overridden, codec preserved).
  assert.deepEqual(stone.config.encoding, { bitrate: 256, codec: "opus" });
  // Arrays: replaced entirely.
  assert.deepEqual(stone.config.tags, ["x"]);
  // Primitives: replaced.
  assert.equal(stone.config.volume, 1.0);
  await env.cleanup();
});

test("null in patch sets key to null", async () => {
  const env = await createTestProject("cs-null");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);

  const stone = new MockStone({
    project: env.project,
    id: "null-stone",
    configStore: store,
  });
  stone.config.volume = 0.8;

  await writeFile(
    configPath,
    JSON.stringify({ "null-stone": { volume: null } }),
  );

  await stone.getHash();
  assert.equal(stone.config.volume, null);
  await env.cleanup();
});

test("setPatch writes JSON to expected path; load reads it back (round-trip)", async () => {
  const env = await createTestProject("cs-roundtrip");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);

  const stone = new MockStone({
    project: env.project,
    id: "rt-stone",
    configStore: store,
  });
  stone.config.quality = 5;

  // Trigger baseline capture.
  await stone.getHash();

  await store.setPatch(stone, { quality: 10 });
  assert.equal(stone.config.quality, 10);

  // Read back file and verify.
  const content = JSON.parse(await readFile(configPath, "utf-8"));
  assert.deepEqual(content["rt-stone"], { quality: 10 });

  // New store reading same file gets same patch.
  const store2 = new ConfigStore(configPath);
  const stone2 = new MockStone({
    project: env.project,
    id: "rt-stone",
    configStore: store2,
  });
  stone2.config.quality = 5;
  await stone2.getHash();
  assert.equal(stone2.config.quality, 10);
  await env.cleanup();
});

test("Re-apply from baseline is idempotent", async () => {
  const env = await createTestProject("cs-idempotent");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);

  const stone = new MockStone({
    project: env.project,
    id: "idem-stone",
    configStore: store,
  });
  stone.config.level = 3;

  await writeFile(
    configPath,
    JSON.stringify({ "idem-stone": { level: 7 } }),
  );

  // Apply once.
  await stone.getHash();
  assert.equal(stone.config.level, 7);

  // Force file stat change (rewrite same content after small delay).
  await new Promise((r) => setTimeout(r, 50));
  await writeFile(
    configPath,
    JSON.stringify({ "idem-stone": { level: 7 } }),
  );

  // Apply again — should still be 7, not compounded.
  await stone.getHash();
  assert.equal(stone.config.level, 7);

  // Change patch back to empty — baseline should restore.
  await new Promise((r) => setTimeout(r, 50));
  await writeFile(configPath, JSON.stringify({}));

  await stone.getHash();
  assert.equal(stone.config.level, 3);
  await env.cleanup();
});

test("Structural fields (Router, Stone instances, functions) are excluded from baseline/patching", async () => {
  const env = await createTestProject("cs-structural");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);

  const source = new MockStone({ project: env.project, id: "source-dep" });
  const router = new Router(source);
  const stone = new MockStone({
    project: env.project,
    id: "struct-stone",
    configStore: store,
  });
  stone.config.myRouter = router;
  stone.config.myStone = source;
  stone.config.myFunc = () => 42;
  stone.config.myData = "editable";

  await writeFile(
    configPath,
    JSON.stringify({ "struct-stone": { myData: "patched" } }),
  );

  await stone.getHash();

  // Structural fields preserved as-is.
  assert.equal(stone.config.myRouter, router);
  assert.equal(stone.config.myStone, source);
  assert.equal(typeof stone.config.myFunc, "function");
  // Data field patched.
  assert.equal(stone.config.myData, "patched");
  await env.cleanup();
});

test("Unknown stone IDs in the file are preserved", async () => {
  const env = await createTestProject("cs-unknown-ids");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);

  const stone = new MockStone({
    project: env.project,
    id: "known-stone",
    configStore: store,
  });
  stone.config.val = 1;

  await writeFile(
    configPath,
    JSON.stringify({
      "known-stone": { val: 2 },
      "future-stone": { something: true },
    }),
  );

  await stone.getHash();
  assert.equal(stone.config.val, 2);

  // Write back via setPatch — future-stone entry should survive.
  await store.setPatch(stone, { val: 3 });
  const content = JSON.parse(await readFile(configPath, "utf-8"));
  assert.deepEqual(content["future-stone"], { something: true });
  assert.deepEqual(content["known-stone"], { val: 3 });
  await env.cleanup();
});

test("Multiple stones sharing same ConfigStore instance work independently", async () => {
  const env = await createTestProject("cs-multi");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);

  const stone1 = new MockStone({
    project: env.project,
    id: "stone-a",
    configStore: store,
  });
  stone1.config.val = 10;

  const stone2 = new MockStone({
    project: env.project,
    id: "stone-b",
    configStore: store,
  });
  stone2.config.val = 20;

  await writeFile(
    configPath,
    JSON.stringify({
      "stone-a": { val: 100 },
      "stone-b": { val: 200 },
    }),
  );

  await stone1.getHash();
  await stone2.getHash();

  assert.equal(stone1.config.val, 100);
  assert.equal(stone2.config.val, 200);
  await env.cleanup();
});

test("Project-level ConfigStore applies to stones without explicit configStore", async () => {
  const env = await createTestProject("cs-project-level");
  const configPath = path.join(env.rootDir, "config.json");

  // Create a new project with configStore.
  const store = new ConfigStore(configPath);
  const project = new Project({
    name: "cs-proj",
    rootDir: env.rootDir,
    configStore: store,
  });

  const stone = new MockStone({ project, id: "proj-stone" });
  stone.config.val = 1;

  await writeFile(
    configPath,
    JSON.stringify({ "proj-stone": { val: 99 } }),
  );

  await stone.getHash();
  assert.equal(stone.config.val, 99);
  await project.cache.close();
});

test("Stone-level configStore overrides project-level", async () => {
  const env = await createTestProject("cs-override");
  const projPath = path.join(env.rootDir, "proj-config.json");
  const stonePath = path.join(env.rootDir, "stone-config.json");

  const projStore = new ConfigStore(projPath);
  const stoneStore = new ConfigStore(stonePath);
  const project = new Project({
    name: "cs-override",
    rootDir: env.rootDir,
    configStore: projStore,
  });

  const stone = new MockStone({
    project,
    id: "over-stone",
    configStore: stoneStore,
  });
  stone.config.val = 1;

  await writeFile(
    projPath,
    JSON.stringify({ "over-stone": { val: 50 } }),
  );
  await writeFile(
    stonePath,
    JSON.stringify({ "over-stone": { val: 77 } }),
  );

  await stone.getHash();
  // Stone-level store should win.
  assert.equal(stone.config.val, 77);
  await project.cache.close();
});

test("Stale file detection: mtime change triggers reload and re-apply", async () => {
  const env = await createTestProject("cs-stale");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);

  const stone = new MockStone({
    project: env.project,
    id: "stale-stone",
    configStore: store,
  });
  stone.config.val = 1;

  await writeFile(
    configPath,
    JSON.stringify({ "stale-stone": { val: 10 } }),
  );

  await stone.getHash();
  assert.equal(stone.config.val, 10);

  // Change file with delay to ensure mtime differs.
  await new Promise((r) => setTimeout(r, 50));
  await writeFile(
    configPath,
    JSON.stringify({ "stale-stone": { val: 20 } }),
  );

  await stone.getHash();
  assert.equal(stone.config.val, 20);
  await env.cleanup();
});

test("Entry unchanged after file reload: no unnecessary config mutation", async () => {
  const env = await createTestProject("cs-no-mutate");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);

  const stone = new MockStone({
    project: env.project,
    id: "nomut-stone",
    configStore: store,
  });
  stone.config.nested = { a: 1, b: 2 };

  await writeFile(
    configPath,
    JSON.stringify({
      "nomut-stone": { nested: { a: 10 } },
      "other-stone": { x: 1 },
    }),
  );

  await stone.getHash();
  const firstRef = stone.config.nested;
  assert.deepEqual(firstRef, { a: 10, b: 2 });

  // Rewrite file but only change other-stone's entry.
  await new Promise((r) => setTimeout(r, 50));
  await writeFile(
    configPath,
    JSON.stringify({
      "nomut-stone": { nested: { a: 10 } },
      "other-stone": { x: 2 },
    }),
  );

  await stone.getHash();
  // Config should still have same value.
  assert.deepEqual(stone.config.nested, { a: 10, b: 2 });
  await env.cleanup();
});

test("configStore field itself excluded from fromConfig hashing", async () => {
  const env = await createTestProject("cs-hash-excl");
  const store = new ConfigStore(
    path.join(env.rootDir, "config.json"),
  );

  const stone1 = new MockStone({
    project: env.project,
    id: "hash-a",
    configStore: store,
  });

  const stone2 = new MockStone({
    project: env.project,
    id: "hash-b",
    // No configStore.
  });

  // Both have same hashKey → hashes should be equal
  // (configStore field must not affect fromConfig hash).
  const hash1 = await SourceHash.fromConfig(stone1.config);
  const hash2 = await SourceHash.fromConfig(stone2.config);
  assert.ok(SourceHash.equals(hash1, hash2));
  await env.cleanup();
});

test("Config patching happens before hash computation", async () => {
  const env = await createTestProject("cs-before-hash");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);

  // Stone uses hashKey derived from config.label — patch changes label → changes hash.
  const stone = new MockStone({
    project: env.project,
    id: "hashchk",
    configStore: store,
    hashKey: (s) => s.config.label,
    cacheStrategy: CacheStrategy.None,
  });
  stone.config.label = "original";

  // No config file yet — label stays "original".
  const hash1 = await stone.getHash();

  // Now patch label.
  await writeFile(
    configPath,
    JSON.stringify({ hashchk: { label: "patched" } }),
  );

  const hash2 = await stone.getHash();

  // Hashes must differ because label was patched before hash computation.
  assert.ok(!SourceHash.equals(hash1, hash2));
  await env.cleanup();
});
