import test from "node:test";
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { ConfigStore, Project, Router } from "../bin/whet.js";
import { SourceHash } from "../bin/whet/SourceHash.js";
import { CacheStrategy } from "../bin/whet/cache/Cache.js";
import { MockStone } from "./helpers/mock-stone.mjs";
import { createTestProject } from "./helpers/test-env.mjs";

test("getStoneConfig returns null for unknown stone ID", async () => {
  const env = await createTestProject("cfg-api-unknown");
  const result = await env.project.getStoneConfig("nonexistent");
  assert.equal(result, null);
  await env.cleanup();
});

test("setStoneConfig returns false for unknown stone ID", async () => {
  const env = await createTestProject("cfg-api-set-unknown");
  const result = await env.project.setStoneConfig("nonexistent", { val: 1 }, "preview");
  assert.equal(result, false);
  await env.cleanup();
});

test("setStoneConfig returns false when no ConfigStore is available", async () => {
  const env = await createTestProject("cfg-api-no-store");
  const stone = new MockStone({ project: env.project, id: "no-store" });
  stone.config.val = 1;
  const result = await env.project.setStoneConfig("no-store", { val: 2 }, "preview");
  assert.equal(result, false);
  await env.cleanup();
});

test("clearStoneConfigPreview returns false for unknown stone ID", async () => {
  const env = await createTestProject("cfg-api-clear-unknown");
  const result = await env.project.clearStoneConfigPreview("nonexistent");
  assert.equal(result, false);
  await env.cleanup();
});

test("clearStoneConfigPreview returns false when no ConfigStore", async () => {
  const env = await createTestProject("cfg-api-clear-nostore");
  new MockStone({ project: env.project, id: "no-store" });
  const result = await env.project.clearStoneConfigPreview("no-store");
  assert.equal(result, false);
  await env.cleanup();
});

test("getStoneConfig excludes runtime objects from editable", async () => {
  const env = await createTestProject("cfg-api-editable");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);
  const project = new Project({
    name: "cfg-editable",
    rootDir: env.rootDir,
    configStore: store,
  });

  const dep = new MockStone({ project, id: "dep-stone" });
  const router = new Router(dep);
  const stone = new MockStone({ project, id: "edit-stone" });
  stone.config.myRouter = router;
  stone.config.myStone = dep;
  stone.config.myFunc = () => 42;
  stone.config.myData = "visible";
  stone.config.nested = { a: 1 };

  const view = await project.getStoneConfig("edit-stone");
  assert.ok(view != null);
  assert.equal(view.id, "edit-stone");
  // Runtime objects excluded.
  assert.equal(view.editable.myRouter, undefined);
  assert.equal(view.editable.myStone, undefined);
  assert.equal(view.editable.myFunc, undefined);
  // StoneConfig base keys excluded.
  assert.equal(view.editable.cacheStrategy, undefined);
  assert.equal(view.editable.id, undefined);
  assert.equal(view.editable.project, undefined);
  assert.equal(view.editable.dependencies, undefined);
  assert.equal(view.editable.configStore, undefined);
  // JSON-serializable data included.
  assert.equal(view.editable.myData, "visible");
  assert.deepEqual(view.editable.nested, { a: 1 });
  await project.cache.close();
});

test("getStoneConfig includes metadata", async () => {
  const env = await createTestProject("cfg-api-meta");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);
  const project = new Project({
    name: "cfg-meta",
    rootDir: env.rootDir,
    configStore: store,
  });

  const dep = new MockStone({ project, id: "meta-dep" });
  const stone = new MockStone({ project, id: "meta-stone", dependencies: dep });

  const view = await project.getStoneConfig("meta-stone");
  assert.ok(view != null);
  assert.equal(view.meta.className, "MockStone");
  assert.ok(view.meta.cacheStrategy != null);
  assert.deepEqual(view.meta.dependencyIds, ["meta-dep"]);
  assert.equal(view.meta.hasStoneConfigStore, false);
  assert.equal(view.meta.hasProjectConfigStore, true);
  await project.cache.close();
});

test("getStoneConfig reflects hasStoneConfigStore when stone has its own store", async () => {
  const env = await createTestProject("cfg-api-store-flags");
  const stoneStore = new ConfigStore(path.join(env.rootDir, "stone.json"));
  const stone = new MockStone({
    project: env.project,
    id: "flagged",
    configStore: stoneStore,
  });

  const view = await env.project.getStoneConfig("flagged");
  assert.equal(view.meta.hasStoneConfigStore, true);
  assert.equal(view.meta.hasProjectConfigStore, false);
  await env.cleanup();
});

test("preview updates effective config for generation and does not write file", async () => {
  const env = await createTestProject("cfg-api-preview");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);
  const project = new Project({
    name: "cfg-preview",
    rootDir: env.rootDir,
    configStore: store,
  });

  const stone = new MockStone({
    project,
    id: "prev-stone",
    hashKey: (s) => s.config.label,
    cacheStrategy: CacheStrategy.None,
  });
  stone.config.label = "original";

  // Capture hash before preview.
  const hash1 = await stone.getHash();

  // Preview mode: update in memory only.
  const ok = await project.setStoneConfig("prev-stone", { label: "previewed" }, "preview");
  assert.equal(ok, true);

  // Next getHash triggers ensureApplied which detects change.
  const hash2 = await stone.getHash();
  assert.equal(stone.config.label, "previewed");
  assert.ok(!SourceHash.equals(hash1, hash2));

  // File should NOT exist.
  let fileExists = true;
  try {
    await readFile(configPath, "utf-8");
  } catch {
    fileExists = false;
  }
  assert.equal(fileExists, false);
  await project.cache.close();
});

test("persist updates effective config and writes file", async () => {
  const env = await createTestProject("cfg-api-persist");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);
  const project = new Project({
    name: "cfg-persist",
    rootDir: env.rootDir,
    configStore: store,
  });

  const stone = new MockStone({ project, id: "pers-stone" });
  stone.config.val = 1;

  const ok = await project.setStoneConfig("pers-stone", { val: 42 }, "persist");
  assert.equal(ok, true);

  // ensureApplied on next access picks up the change.
  await stone.getHash();
  assert.equal(stone.config.val, 42);

  // File should exist with the entry.
  const content = JSON.parse(await readFile(configPath, "utf-8"));
  assert.deepEqual(content["pers-stone"], { val: 42 });
  await project.cache.close();
});

test("persist is replace semantics for the whole entry", async () => {
  const env = await createTestProject("cfg-api-replace");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);
  const project = new Project({
    name: "cfg-replace",
    rootDir: env.rootDir,
    configStore: store,
  });

  const stone = new MockStone({ project, id: "repl-stone" });
  stone.config.a = 1;
  stone.config.b = 2;

  // First persist with both keys.
  await project.setStoneConfig("repl-stone", { a: 10, b: 20 }, "persist");
  await stone.getHash();
  assert.equal(stone.config.a, 10);
  assert.equal(stone.config.b, 20);

  // Second persist with only key `a` — entry replaces entirely.
  await project.setStoneConfig("repl-stone", { a: 99 }, "persist");
  await stone.getHash();
  assert.equal(stone.config.a, 99);
  // `b` should revert to baseline since new entry doesn't include it.
  assert.equal(stone.config.b, 2);
  await project.cache.close();
});

test("clearStoneConfigPreview removes in-memory entry and restores persisted result", async () => {
  const env = await createTestProject("cfg-api-clear");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);
  const project = new Project({
    name: "cfg-clear",
    rootDir: env.rootDir,
    configStore: store,
  });

  const stone = new MockStone({ project, id: "clr-stone" });
  stone.config.val = 1;

  // Persist a value first.
  await project.setStoneConfig("clr-stone", { val: 50 }, "persist");
  await stone.getHash();
  assert.equal(stone.config.val, 50);

  // Preview a different value.
  await project.setStoneConfig("clr-stone", { val: 999 }, "preview");
  await stone.getHash();
  assert.equal(stone.config.val, 999);

  // Clear preview — should restore to persisted value (50).
  const ok = await project.clearStoneConfigPreview("clr-stone");
  assert.equal(ok, true);
  await stone.getHash();
  assert.equal(stone.config.val, 50);
  await project.cache.close();
});

test("clearStoneConfigPreview restores baseline when nothing persisted", async () => {
  const env = await createTestProject("cfg-api-clear-base");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);
  const project = new Project({
    name: "cfg-clear-base",
    rootDir: env.rootDir,
    configStore: store,
  });

  const stone = new MockStone({ project, id: "clrb-stone" });
  stone.config.val = 1;

  // Preview without prior persist.
  await project.setStoneConfig("clrb-stone", { val: 777 }, "preview");
  await stone.getHash();
  assert.equal(stone.config.val, 777);

  // Clear — should restore to baseline (1).
  await project.clearStoneConfigPreview("clrb-stone");
  await stone.getHash();
  assert.equal(stone.config.val, 1);
  await project.cache.close();
});

test("isDirty tracks preview vs persisted state", async () => {
  const env = await createTestProject("cfg-api-dirty");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);
  const project = new Project({
    name: "cfg-dirty",
    rootDir: env.rootDir,
    configStore: store,
  });

  const stone = new MockStone({ project, id: "dirty-stone" });
  stone.config.val = 1;

  // Initial state: not dirty.
  await stone.getHash(); // triggers ensureApplied → reload → initializes persistedData
  assert.equal(store.isDirty("dirty-stone"), false);
  assert.equal(store.isDirty(), false);

  // Preview makes it dirty.
  store.setEntry("dirty-stone", { val: 99 });
  assert.equal(store.isDirty("dirty-stone"), true);
  assert.equal(store.isDirty(), true);

  // Flush makes it clean again.
  await store.flush();
  assert.equal(store.isDirty("dirty-stone"), false);
  assert.equal(store.isDirty(), false);
  await project.cache.close();
});

test("preview on one stone does not affect another stone's preview", async () => {
  const env = await createTestProject("cfg-api-multi-preview");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);
  const project = new Project({
    name: "cfg-multi",
    rootDir: env.rootDir,
    configStore: store,
  });

  const stone1 = new MockStone({ project, id: "multi-a" });
  stone1.config.val = 1;
  const stone2 = new MockStone({ project, id: "multi-b" });
  stone2.config.val = 2;

  // Preview both stones.
  await project.setStoneConfig("multi-a", { val: 100 }, "preview");
  await project.setStoneConfig("multi-b", { val: 200 }, "preview");
  await stone1.getHash();
  await stone2.getHash();
  assert.equal(stone1.config.val, 100);
  assert.equal(stone2.config.val, 200);

  // Clear only stone A — stone B should keep its preview.
  await project.clearStoneConfigPreview("multi-a");
  await stone1.getHash();
  await stone2.getHash();
  assert.equal(stone1.config.val, 1);
  assert.equal(stone2.config.val, 200);
  await project.cache.close();
});

test("getStoneConfig editable is a deep clone (not a reference to config)", async () => {
  const env = await createTestProject("cfg-api-clone");
  const configPath = path.join(env.rootDir, "config.json");
  const store = new ConfigStore(configPath);
  const project = new Project({
    name: "cfg-clone",
    rootDir: env.rootDir,
    configStore: store,
  });

  const stone = new MockStone({ project, id: "clone-stone" });
  stone.config.nested = { a: 1 };

  const view = await project.getStoneConfig("clone-stone");
  // Mutating the returned editable should not affect the stone.
  view.editable.nested.a = 999;
  assert.equal(stone.config.nested.a, 1);
  await project.cache.close();
});
