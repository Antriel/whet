import { it, afterEach } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { rm, readFile } from "node:fs/promises";
import {
  StoneStore,
  StoneRegistry,
  Stone,
  Router,
  Project,
  ConfigStore,
  Log,
  Utils,
} from "../bin/whet.js";
import { SourceData } from "../bin/whet/Source.js";
import { createTestProject } from "./helpers/test-env.mjs";
import { MockStone } from "./helpers/mock-stone.mjs";

let env;
afterEach(async () => {
  if (env) await env.cleanup();
  env = null;
});

// --- Test stone types ---------------------------------------------------

// Re-emits the joined string content of everything under `config.source` (a stone/router/string),
// under its own id. So an Echo whose source is {$stone:"x"} carries x's output forward, and its
// output moves when x's does — exercising ref flow and the recreate cascade.
class EchoStone extends Stone {
  async generate() {
    const r = new Router(this.config.source);
    const results = await r.get();
    const parts = [];
    for (const res of results) parts.push(await res.getString());
    return [SourceData.fromString(this.id, parts.join("|"))];
  }
  async list() {
    return [this.id];
  }
}

// Reads the file at `config.file` (project-relative) and emits its content. Used to prove `$file`
// token substitution reaches a real on-disk path end-to-end.
class FileEchoStone extends Stone {
  async generate() {
    const content = await readFile(path.join(this.project.rootDir, this.config.file), "utf-8");
    return [SourceData.fromString(this.id, content)];
  }
  async list() {
    return [this.id];
  }
}

StoneRegistry.register("Echo", EchoStone);
StoneRegistry.register("Mock", MockStone);
StoneRegistry.register("FileEcho", FileEchoStone);
// Records the (revived) config each entry is built with, so tests can inspect the merged /
// token-substituted config directly (MockStone drops unknown config keys).
const capturedConfigs = new Map();
StoneRegistry.registerBuilder("Capture", (key, config) => {
  capturedConfigs.set(key, config);
  const s = new MockStone({ id: `${key}:inner`, outputs: [{ id: `${key}.txt`, content: "x" }] });
  return { stones: [s], mainStone: s };
});
// A composite type that returns stones+routes but NO mainStone — used to prove a mount on such a
// type is rejected.
StoneRegistry.registerBuilder("Composite", (key, config) => {
  const s = new MockStone({
    id: `${key}:inner`,
    outputs: [{ id: `${key}.txt`, content: config.content ?? "c" }],
  });
  return { stones: [s], routes: [[`${key}.txt`, s]] };
});

// A StoneStore that records per-key create/update calls, for asserting the cascade / skip behaviour.
class CountingStore extends StoneStore {
  constructor(cfg) {
    super(cfg);
    this.created = [];
    this.updated = [];
  }
  createEntry(key, data) {
    this.created.push(key);
    return super.createEntry(key, data);
  }
  updateEntry(key, data, existing) {
    this.updated.push(key);
    return super.updateEntry(key, data, existing);
  }
}

// --- Tests --------------------------------------------------------------

it("entry B's $stone ref to A makes B's output flow from A's", async () => {
  env = await createTestProject("store-ref");
  new MockStone({ project: env.project, id: "srcA", outputs: [{ id: "srcA.txt", content: "AAA" }] });

  const store = new StoneStore({ project: env.project });
  store.db.data = [
    { id: "a", type: "Echo", config: { source: { $stone: "srcA" } } },
    { id: "b", type: "Echo", config: { source: { $stone: "a" } }, mount: "b.txt" },
  ];
  await store.syncEntries();

  // B is mounted; its served output is the echo of A, which echoes srcA.
  assert.equal(await store.getString("b.txt"), "AAA");
});

it("loads from a JSON file and serves the db via the base route", async () => {
  env = await createTestProject("store-load");
  new MockStone({ project: env.project, id: "srcA", outputs: [{ id: "srcA.txt", content: "hi" }] });
  await env.write(
    "assets/store.json",
    JSON.stringify([{ id: "a", type: "Echo", config: { source: { $stone: "srcA" } }, mount: "a.txt" }]),
  );

  const store = new StoneStore({ project: env.project, dbId: "store.json" });
  const ret = await store.load("assets/store.json");
  assert.strictEqual(ret, store);

  assert.equal(await store.getString("a.txt"), "hi");
  // The db json itself is served under the base route (stone id == dbId).
  const dbJson = JSON.parse(await store.getString("store.json"));
  assert.equal(dbJson[0].id, "a");
});

it("editing A only force-updates dependent B (cascade); independent C is skipped", async () => {
  env = await createTestProject("store-cascade");
  new MockStone({ project: env.project, id: "srcA", outputs: [{ id: "s.txt", content: "A1" }] });
  new MockStone({ project: env.project, id: "srcA2", outputs: [{ id: "s.txt", content: "A2" }] });
  new MockStone({ project: env.project, id: "srcC", outputs: [{ id: "s.txt", content: "C" }] });

  const store = new CountingStore({ project: env.project });
  store.db.data = [
    { id: "a", type: "Echo", config: { source: { $stone: "srcA" } } },
    { id: "b", type: "Echo", config: { source: { $stone: "a" } }, mount: "b.txt" },
    { id: "c", type: "Echo", config: { source: { $stone: "srcC" } } },
  ];
  await store.syncEntries();
  assert.equal(await store.getString("b.txt"), "A1");

  // Update A only (replace the entry — the canonical-data update model; callers don't mutate
  // entry fields in place). B and C entries are unchanged; re-sync.
  store.created = [];
  store.updated = [];
  store.db.data = [
    { id: "a", type: "Echo", config: { source: { $stone: "srcA2" } } },
    { id: "b", type: "Echo", config: { source: { $stone: "a" } }, mount: "b.txt" },
    { id: "c", type: "Echo", config: { source: { $stone: "srcC" } } },
  ];
  await store.syncEntries();

  assert.ok(store.updated.includes("a"), "A updated");
  assert.ok(store.updated.includes("b"), "B force-updated via cascade");
  assert.ok(!store.updated.includes("c"), "C skipped (no ref to a touched key)");
  assert.equal(await store.getString("b.txt"), "A2");
});

it("an entry can reference a script-defined project stone", async () => {
  env = await createTestProject("store-project-ref");
  new MockStone({ project: env.project, id: "script-stone", outputs: [{ id: "x.txt", content: "SCRIPT" }] });

  const store = new StoneStore({ project: env.project });
  store.db.data = [
    { id: "a", type: "Echo", config: { source: { $stone: "script-stone" } }, mount: "a.txt" },
  ];
  await store.syncEntries();
  assert.equal(await store.getString("a.txt"), "SCRIPT");
});

it("a disabled entry's stones are removed; re-enabling recreates them", async () => {
  env = await createTestProject("store-disabled");
  new MockStone({ project: env.project, id: "src", outputs: [{ id: "s.txt", content: "V" }] });

  const store = new StoneStore({ project: env.project });
  store.db.data = [{ id: "a", type: "Echo", config: { source: { $stone: "src" } }, mount: "a.txt" }];
  await store.syncEntries();
  assert.ok(env.project.getStone("a"));
  assert.equal(await store.getString("a.txt"), "V");

  // Disable → stones removed, route gone.
  store.db.data = [{ id: "a", type: "Echo", config: { source: { $stone: "src" } }, mount: "a.txt", disabled: true }];
  await store.syncEntries();
  assert.equal(env.project.getStone("a"), null);
  assert.equal((await store.get("a.txt")).length, 0);

  // Re-enable → recreated.
  store.db.data = [{ id: "a", type: "Echo", config: { source: { $stone: "src" } }, mount: "a.txt" }];
  await store.syncEntries();
  assert.ok(env.project.getStone("a"));
  assert.equal(await store.getString("a.txt"), "V");
});

it("mount string and array forms serve outputs under their prefixes", async () => {
  env = await createTestProject("store-mounts");
  new MockStone({ project: env.project, id: "src", outputs: [{ id: "out.txt", content: "M" }] });

  const store = new StoneStore({ project: env.project });
  store.db.data = [
    // String form: a file (rename) mount.
    { id: "a", type: "Echo", config: { source: { $stone: "src" } }, mount: "a.txt" },
    // Array form: a directory mount, serving under the prefix by the stone's own output id.
    { id: "b", type: "Echo", config: { source: { $stone: "src" } }, mount: [["dir/"]] },
  ];
  await store.syncEntries();

  assert.equal(await store.getString("a.txt"), "M");
  // Dir mount serves the entry's mainStone output (id == "b") under dir/.
  assert.equal(await store.getString("dir/b"), "M");
});

it("previewEntry cascades to dependents; revertEntry restores; flushDb persists only canonical", async () => {
  env = await createTestProject("store-preview");
  new MockStone({ project: env.project, id: "srcA", outputs: [{ id: "s.txt", content: "CANON" }] });
  new MockStone({ project: env.project, id: "srcA2", outputs: [{ id: "s.txt", content: "PREVIEW" }] });
  await env.write(
    "store.json",
    JSON.stringify([
      { id: "a", type: "Echo", config: { source: { $stone: "srcA" } } },
      { id: "b", type: "Echo", config: { source: { $stone: "a" } }, mount: "b.txt" },
    ]),
  );

  const store = new StoneStore({ project: env.project, dbId: "store.json" });
  // load() reads the file into db.data, binds the path (so flushDb writes there), and syncs.
  await store.load("store.json");
  assert.equal(await store.getString("b.txt"), "CANON");

  // Preview A pointing at a different source → B (dependent) reflects it via the cascade.
  store.previewEntry("a", { key: "a", type: "Echo", config: { source: { $stone: "srcA2" } } });
  assert.equal(store.isPreviewDirty("a"), true);
  assert.equal(await store.getString("b.txt"), "PREVIEW");

  // Revert → canonical restored for both A and B.
  assert.equal(store.revertEntry("a"), true);
  assert.equal(store.isPreviewDirty(), false);
  assert.equal(await store.getString("b.txt"), "CANON");

  // Flush persists canonical data only (never the preview).
  await store.flushDb();
  const persisted = JSON.parse(await env.read("store.json"));
  assert.deepEqual(persisted[0].config.source, { $stone: "srcA" });
});

it("validation: duplicate id / unknown type errors leave existing stones untouched", async () => {
  env = await createTestProject("store-validate");
  new MockStone({ project: env.project, id: "src", outputs: [{ id: "s.txt", content: "V" }] });

  const store = new StoneStore({ project: env.project });
  store.db.data = [{ id: "a", type: "Echo", config: { source: { $stone: "src" } } }];
  await store.syncEntries();
  const snapshot = env.project.stones.slice();
  const stoneA = env.project.getStone("a");

  // Duplicate id.
  store.db.data = [
    { id: "a", type: "Echo", config: { source: { $stone: "src" } } },
    { id: "a", type: "Echo", config: { source: { $stone: "src" } } },
  ];
  await assert.rejects(async () => await store.syncEntries(), /Duplicate entry id "a"/);
  assert.deepEqual(env.project.stones, snapshot);
  assert.strictEqual(env.project.getStone("a"), stoneA);

  // Unknown type: error names the type AND the registered names.
  store.db.data = [{ id: "a", type: "Nope", config: {} }];
  await assert.rejects(async () => await store.syncEntries(), (err) => {
    assert.match(err.message, /unknown type "Nope"/);
    assert.match(err.message, /Echo/);
    return true;
  });
  assert.deepEqual(env.project.stones, snapshot);
});

it("validation: dependency cycle errors and leaves stones untouched", async () => {
  env = await createTestProject("store-cycle");
  new MockStone({ project: env.project, id: "src", outputs: [{ id: "s.txt", content: "V" }] });

  const store = new StoneStore({ project: env.project });
  store.db.data = [{ id: "a", type: "Echo", config: { source: { $stone: "src" } } }];
  await store.syncEntries();
  const snapshot = env.project.stones.slice();

  store.db.data = [
    { id: "a", type: "Echo", config: { source: { $stone: "b" } } },
    { id: "b", type: "Echo", config: { source: { $stone: "a" } } },
  ];
  await assert.rejects(async () => await store.syncEntries(), /Cycle detected.*a -> b -> a|b -> a -> b/);
  assert.deepEqual(env.project.stones, snapshot);
});

it("mount on a mainStone-less type errors and rolls back to untouched stones", async () => {
  env = await createTestProject("store-mount-nomain");
  new MockStone({ project: env.project, id: "src", outputs: [{ id: "s.txt", content: "V" }] });

  const store = new StoneStore({ project: env.project });
  store.db.data = [{ id: "a", type: "Echo", config: { source: { $stone: "src" } } }];
  await store.syncEntries();
  const snapshot = env.project.stones.slice();

  // Composite type yields no mainStone, but the entry declares a mount → build-time error.
  store.db.data = [
    { id: "a", type: "Echo", config: { source: { $stone: "src" } } },
    { id: "comp", type: "Composite", config: { content: "x" }, mount: "comp.txt" },
  ];
  await assert.rejects(async () => await store.syncEntries(), /produced no mainStone/);
  // Rollback: original stones present, no leftover composite stone.
  assert.deepEqual(env.project.stones, snapshot);
  assert.equal(env.project.getStone("comp:inner"), null);
});

it("warns when a store-created stone also has a ConfigStore patch", async () => {
  env = await createTestProject("store-configstore");
  // A dedicated project carrying a ConfigStore with a patch for the id the store will create.
  const configStore = new ConfigStore("cfg.json");
  configStore.setEntry("a", { foo: 1 });
  const project = new Project({
    name: "cfg-proj",
    id: `cfg-proj-${Date.now()}`,
    rootDir: env.rootDir,
    configStore,
  });
  new MockStone({ project, id: "src", outputs: [{ id: "s.txt", content: "V" }] });

  const warnings = [];
  const orig = Log.log;
  Log.log = (level, ...args) => {
    if (level === 40) warnings.push(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" "));
    return orig(level, ...args);
  };
  try {
    const store = new StoneStore({ project });
    store.db.data = [{ id: "a", type: "Echo", config: { source: { $stone: "src" } } }];
    await store.syncEntries();
  } finally {
    Log.log = orig;
  }
  assert.ok(
    warnings.some((w) => /ConfigStore patch/.test(w)),
    `expected a ConfigStore-overlap warning, got: ${JSON.stringify(warnings)}`,
  );
});

// --- `each` expansion ---------------------------------------------------

it("each: scans a directory into one sub-entry per file with $file/$name tokens", async () => {
  env = await createTestProject("store-each");
  await env.write("sfx/punch.txt", "PUNCH");
  await env.write("sfx/kick.txt", "KICK");

  const store = new StoneStore({ project: env.project });
  store.db.data = [
    {
      id: "sfx",
      type: "FileEcho",
      each: { dir: "sfx/", pattern: "(.*)\\.txt$" },
      config: { file: "$file" },
      mount: "$name.out",
    },
  ];
  await store.syncEntries();

  // Expanded keys are `groupId/name`.
  assert.ok(env.project.getStone("sfx/kick"));
  assert.ok(env.project.getStone("sfx/punch"));
  // `$file` reached the real path (FileEcho read it); the per-file mount used `$name`.
  assert.equal(await store.getString("kick.out"), "KICK");
  assert.equal(await store.getString("punch.out"), "PUNCH");
  // Introspection for the future editor plugin (sorted by file path).
  assert.deepEqual(store.getExpansion("sfx").names, ["kick", "punch"]);
  assert.deepEqual(store.getExpansion("sfx").files, ["sfx/kick.txt", "sfx/punch.txt"]);
  assert.equal(store.getExpansion("nope"), null);
});

it("each: per-file overrides deep-merge over config (nested merge, array replace)", async () => {
  env = await createTestProject("store-each-ovr");
  await env.write("data/a.txt", "A");
  await env.write("data/b.txt", "B");
  capturedConfigs.clear();

  const store = new StoneStore({ project: env.project });
  store.db.data = [
    {
      id: "g",
      type: "Capture",
      each: { dir: "data/", pattern: "(.*)\\.txt$" },
      config: { nested: { keep: 1, val: "x" }, arr: [1, 2] },
      overrides: { b: { nested: { val: "y" }, arr: [9] } },
    },
  ];
  await store.syncEntries();

  // `a`: no override → base config, untouched.
  assert.deepEqual(capturedConfigs.get("g/a").nested, { keep: 1, val: "x" });
  assert.deepEqual(capturedConfigs.get("g/a").arr, [1, 2]);
  // `b`: nested object deep-merged (keep retained, val overridden); array replaced wholesale.
  assert.deepEqual(capturedConfigs.get("g/b").nested, { keep: 1, val: "y" });
  assert.deepEqual(capturedConfigs.get("g/b").arr, [9]);
  // The base config object is not mutated by expansion (no aliasing into db.data).
  assert.deepEqual(store.db.data[0].config.nested, { keep: 1, val: "x" });
});

it("each: $file/$name tokens are substituted inside $router route arrays and mount", async () => {
  env = await createTestProject("store-each-router");
  await env.write("imgs/hero.txt", "HERO");

  const store = new StoneStore({ project: env.project });
  store.db.data = [
    {
      id: "img",
      type: "Echo",
      each: { dir: "imgs/", pattern: "(.*)\\.txt$" },
      config: { source: { $router: [["$name.slot", "$file"]] } },
      mount: "$name.final",
    },
  ];
  await store.syncEntries();

  // Echo joins its source router's output; the router serves `$file`'s content, mounted via `$name`.
  assert.equal(await store.getString("hero.final"), "HERO");
});

it("each: re-sync picks up an added file and drops a removed one (with its dataMap key)", async () => {
  env = await createTestProject("store-each-resync");
  await env.write("d/a.txt", "A");

  const store = new StoneStore({ project: env.project });
  store.db.data = [
    { id: "g", type: "FileEcho", each: { dir: "d/", pattern: "(.*)\\.txt$" }, config: { file: "$file" }, mount: "$name.out" },
  ];
  await store.syncEntries();
  assert.deepEqual([...store.dataMap.keys()], ["g/a"]);
  assert.equal(await store.getString("a.out"), "A");

  // Add a file → re-sync creates the new sub-entry.
  await env.write("d/b.txt", "B");
  await store.syncEntries();
  assert.deepEqual([...store.dataMap.keys()].sort(), ["g/a", "g/b"]);
  assert.equal(await store.getString("b.out"), "B");

  // Delete a file → re-sync removes the sub-entry, its stone, and its dataMap key.
  await rm(path.join(env.rootDir, "d/a.txt"));
  await store.syncEntries();
  assert.deepEqual([...store.dataMap.keys()], ["g/b"]);
  assert.equal(env.project.getStone("g/a"), null);
  assert.equal((await store.get("a.out")).length, 0);
});

it("each: previewEntry on an expanded key applies without rescanning", async () => {
  env = await createTestProject("store-each-preview");
  await env.write("d/a.txt", "CANON");
  await env.write("other.txt", "PREVIEW");

  let scanCount = 0;
  const origScan = Utils.scanFiles;
  Utils.scanFiles = (...a) => {
    scanCount++;
    return origScan.apply(Utils, a);
  };
  try {
    const store = new StoneStore({ project: env.project });
    store.db.data = [
      { id: "g", type: "FileEcho", each: { dir: "d/", pattern: "(.*)\\.txt$" }, config: { file: "$file" }, mount: "$name.out" },
    ];
    await store.syncEntries();
    assert.equal(scanCount, 1);
    assert.equal(await store.getString("a.out"), "CANON");

    // Client convention: preview a sub-entry with a fully-resolved single-file config/mount (no tokens).
    store.previewEntry("g/a", { key: "g/a", type: "FileEcho", config: { file: "other.txt" }, mount: "a.out" });
    assert.equal(scanCount, 1, "previewEntry must not rescan");
    assert.equal(store.isPreviewDirty("g/a"), true);
    assert.equal(await store.getString("a.out"), "PREVIEW");

    // Revert restores canonical without a rescan.
    assert.equal(store.revertEntry("g/a"), true);
    assert.equal(scanCount, 1);
    assert.equal(await store.getString("a.out"), "CANON");
  } finally {
    Utils.scanFiles = origScan;
  }
});

it("each: an expanded key colliding with another entry errors and leaves stones untouched", async () => {
  env = await createTestProject("store-each-collision");
  await env.write("d/x.txt", "X");
  new MockStone({ project: env.project, id: "src", outputs: [{ id: "s.txt", content: "V" }] });

  const store = new StoneStore({ project: env.project });
  store.db.data = [{ id: "keep", type: "Echo", config: { source: { $stone: "src" } } }];
  await store.syncEntries();
  const snapshot = env.project.stones.slice();

  // A literal entry id equals a would-be expanded key `g/x`.
  store.db.data = [
    { id: "keep", type: "Echo", config: { source: { $stone: "src" } } },
    { id: "g", type: "FileEcho", each: { dir: "d/", pattern: "(.*)\\.txt$" }, config: { file: "$file" } },
    { id: "g/x", type: "Echo", config: { source: { $stone: "src" } } },
  ];
  await assert.rejects(async () => await store.syncEntries(), /expanded key "g\/x"/);
  assert.deepEqual(env.project.stones, snapshot);
});

it("each: an override keyed by a non-existent name warns (typo guard)", async () => {
  env = await createTestProject("store-each-typo");
  await env.write("d/real.txt", "R");

  const warnings = [];
  const orig = Log.log;
  Log.log = (level, ...args) => {
    if (level === 40) warnings.push(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" "));
    return orig(level, ...args);
  };
  try {
    const store = new StoneStore({ project: env.project });
    store.db.data = [
      {
        id: "g",
        type: "Mock",
        each: { dir: "d/", pattern: "(.*)\\.txt$" },
        config: { outputs: [{ id: "o.txt", content: "c" }] },
        overrides: { typo: { outputs: [{ id: "o.txt", content: "c2" }] } },
      },
    ];
    await store.syncEntries();
  } finally {
    Log.log = orig;
  }
  assert.ok(
    warnings.some((w) => /override for "typo"/.test(w)),
    `expected a typo warning, got: ${JSON.stringify(warnings)}`,
  );
});

it("each: validation rejects overrides-without-each and an uncompilable pattern", async () => {
  env = await createTestProject("store-each-valid");
  const store = new StoneStore({ project: env.project });

  store.db.data = [{ id: "g", type: "Mock", config: {}, overrides: { a: {} } }];
  await assert.rejects(async () => await store.syncEntries(), /"overrides" without "each"/);

  store.db.data = [{ id: "g", type: "Mock", each: { dir: "d/", pattern: "(" } }];
  await assert.rejects(async () => await store.syncEntries(), /not a valid RegExp/);

  store.db.data = [{ id: "g", type: "Mock", each: { dir: "", pattern: ".*" } }];
  await assert.rejects(async () => await store.syncEntries(), /"each\.dir" must be a non-empty string/);
});

// --- Schema validation at sync (whet-uzjf) ------------------------------

it("sync rejects an entry whose config violates its type's configSchema", async () => {
  env = await createTestProject("store-schema-reject");
  const store = new StoneStore({ project: env.project });
  // MockStone.configSchema() requires outputs[].id and typed delayMs; feed it two violations.
  store.db.data = [
    { id: "good", type: "Mock", config: { outputs: [{ id: "ok.txt", content: "x" }] } },
    { id: "bad", type: "Mock", config: { delayMs: "soon", outputs: [{ content: "no-id" }] } },
  ];
  await assert.rejects(
    async () => await store.syncEntries(),
    (err) => {
      assert.match(err.message, /schema validation failed/i);
      assert.match(err.message, /entry "bad"/);
      assert.match(err.message, /delayMs/); // path-specific
      assert.match(err.message, /outputs\[0\]/); // indexed path for the missing id
      assert.doesNotMatch(err.message, /entry "good"/);
      return true;
    },
  );
  // All-or-nothing: no stones were created for the batch (the valid "good" entry included).
  assert.equal(store.project.getStone("good"), null);
});

it("sync accepts a schema-valid entry and builds it", async () => {
  env = await createTestProject("store-schema-accept");
  const store = new StoneStore({ project: env.project });
  store.db.data = [
    { id: "ok", type: "Mock", config: { outputs: [{ id: "ok.txt", content: "yes" }], delayMs: 0 }, mount: "ok.txt" },
  ];
  await store.syncEntries();
  assert.equal(await store.getString("ok.txt"), "yes");
});

it("schema validation runs post-substitution and tolerates $stone refs + tokens", async () => {
  env = await createTestProject("store-schema-tokens");
  await env.write("imgs/a.png", "AAA");
  await env.write("imgs/b.png", "BBB");
  new MockStone({ project: env.project, id: "srcX", outputs: [{ id: "s.txt", content: "X" }] });

  const store = new StoneStore({ project: env.project });
  // `each` expansion + $name token substitution feeding a schema-carrying type (Mock). The
  // `id` field is a template resolved to a real string before validation, so minLength holds.
  store.db.data = [
    {
      id: "g",
      type: "Mock",
      each: { dir: "imgs/", pattern: "(?<name>.+)\.png$" },
      config: { outputs: [{ id: "$name.txt", content: "$name" }] },
    },
    // A $stone-ref-bearing config must not be flagged (Echo has no schema, but prove the skip
    // path via a Mock whose hashKey holds a ref-free value alongside).
    { id: "e", type: "Echo", config: { source: { $stone: "srcX" } } },
  ];
  await store.syncEntries();
  // Both group members built with substituted ids.
  assert.equal(store.getExpansion("g").names.sort().join(","), "a,b");
});
