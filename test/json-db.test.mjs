import { it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { stat, utimes } from "node:fs/promises";
import path from "node:path";
import { JsonDb, Router } from "../bin/whet.js";
import { createTestProject } from "./helpers/test-env.mjs";

let env;
afterEach(async () => {
  if (env) await env.cleanup();
  env = null;
});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

it("load: missing file falls back to defaultData", async () => {
  env = await createTestProject("jsondb-missing");
  const db = new JsonDb({ project: env.project, id: "db.json", defaultData: { seeded: true } });
  const ret = await db.load("db.json");
  assert.strictEqual(ret, db); // resolves with `this`
  assert.deepEqual(db.data, { seeded: true });
});

it("load: missing file with no defaultData falls back to []", async () => {
  env = await createTestProject("jsondb-missing-default");
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");
  assert.deepEqual(db.data, []);
});

it("load: existing file is parsed into data", async () => {
  env = await createTestProject("jsondb-existing");
  await env.write("db.json", JSON.stringify([{ name: "a" }, { name: "b" }]));
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");
  assert.deepEqual(db.data, [{ name: "a" }, { name: "b" }]);
});

it("flush: rewrites file with 2-space indent after mutation", async () => {
  env = await createTestProject("jsondb-flush");
  await env.write("db.json", "[]");
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");

  db.data = [{ name: "x", nested: { k: 1 } }];
  await db.flush();

  const written = await env.read("db.json");
  assert.deepEqual(JSON.parse(written), [{ name: "x", nested: { k: 1 } }]);
  // 2-space indent step, byte-identical to haxe.Json.stringify(data, null, '  ').
  assert.ok(written.includes('\n    "name": "x"'), "expected 2-space indent step (object props at 4)");
  assert.ok(written.includes('\n      "k": 1'), "expected nested prop at 6 spaces");
});

it("flush: unchanged data does not rewrite the file", async () => {
  env = await createTestProject("jsondb-flush-noop");
  await env.write("db.json", "[]");
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");

  db.data = [{ v: 1 }];
  await db.flush();
  const filePath = path.join(env.rootDir, "db.json");
  const mtime1 = (await stat(filePath)).mtimeMs;

  await sleep(25); // any real rewrite would land on a later mtime
  await db.flush(); // same data, same hash → cache hit, no write
  const mtime2 = (await stat(filePath)).mtimeMs;
  assert.equal(mtime2, mtime1);

  // Changing the data does rewrite.
  await sleep(25);
  db.data = [{ v: 2 }];
  await db.flush();
  const mtime3 = (await stat(filePath)).mtimeMs;
  assert.notEqual(mtime3, mtime1);
  assert.deepEqual(JSON.parse(await env.read("db.json")), [{ v: 2 }]);
});

it("routed in a Router, serves the JSON under its id", async () => {
  env = await createTestProject("jsondb-route");
  const db = new JsonDb({ project: env.project, id: "config.json" });
  db.data = { hello: "world" };

  const router = new Router(db);
  const results = await router.get();
  assert.deepEqual(results.map((r) => r.serveId), ["config.json"]);
  assert.deepEqual(JSON.parse(await router.getString("config.json")), { hello: "world" });
});

// --- The authored file is an input (whet-vz93) ---------------------------

it("getSource never writes the bound file", async () => {
  env = await createTestProject("jsondb-input");
  await env.write("db.json", '[{"v":1}]');
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");

  db.data = [{ v: 2 }];
  const src = await db.getSource();
  assert.deepEqual(JSON.parse(src.data[0].data.toString()), [{ v: 2 }]); // served from memory
  assert.equal(await env.read("db.json"), '[{"v":1}]'); // file untouched
  assert.equal(db.isDirty(), true);
});

it("isDirty: clean after load, dirty after mutation, clean after save", async () => {
  env = await createTestProject("jsondb-dirty");
  await env.write("db.json", "[]");
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");
  assert.equal(db.isDirty(), false);
  db.data.push({ a: 1 });
  assert.equal(db.isDirty(), true);
  assert.equal(await db.save(), true);
  assert.equal(db.isDirty(), false);
  assert.equal(await db.save(), false); // nothing to write
});

it("save: external edit since load → WHET_FILE_CONFLICT; force overwrites", async () => {
  env = await createTestProject("jsondb-conflict");
  await env.write("db.json", "[]");
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");

  await env.write("db.json", '[{"external":true}]');
  assert.equal(await db.diskChanged(), true);
  db.data = [{ mine: true }];
  await assert.rejects(db.save(), (err) => {
    assert.equal(err.code, "WHET_FILE_CONFLICT");
    assert.ok(err.path.endsWith("db.json"));
    return true;
  });
  assert.deepEqual(JSON.parse(await env.read("db.json")), [{ external: true }]); // not clobbered

  assert.equal(await db.save(true), true);
  assert.deepEqual(JSON.parse(await env.read("db.json")), [{ mine: true }]);
  assert.equal(await db.diskChanged(), false);
});

it("save: file absent at load but created externally → conflict", async () => {
  env = await createTestProject("jsondb-absent");
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");
  await env.write("db.json", '{"someone":"else"}');
  db.data = [{ mine: true }];
  await assert.rejects(db.save(), { code: "WHET_FILE_CONFLICT" });
});

it("save: absent file is created when nobody else did", async () => {
  env = await createTestProject("jsondb-create");
  const db = new JsonDb({ project: env.project, id: "sub/db.json" });
  await db.load("sub/db.json");
  db.data = [{ x: 1 }];
  assert.equal(await db.save(), true);
  assert.deepEqual(JSON.parse(await env.read("sub/db.json")), [{ x: 1 }]);
});

it("save: an mtime-only touch is not a conflict", async () => {
  env = await createTestProject("jsondb-touch");
  await env.write("db.json", "[]");
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");
  const later = new Date(Date.now() + 5000);
  await utimes(path.join(env.rootDir, "db.json"), later, later);
  assert.equal(await db.diskChanged(), false);
  db.data = [1];
  assert.equal(await db.save(), true);
});

it("save: no bound path rejects", async () => {
  env = await createTestProject("jsondb-nopath");
  const db = new JsonDb({ project: env.project, id: "db.json" });
  db.data = [];
  await assert.rejects(db.save(), /no bound path/);
});

it("access picks up an external edit when clean, and fires onReload", async () => {
  env = await createTestProject("jsondb-refresh");
  await env.write("db.json", '[{"v":1}]');
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");
  let reloads = 0;
  db.onReload(() => reloads++);
  assert.deepEqual(JSON.parse(await new Router(db).getString("db.json")), [{ v: 1 }]);

  await env.write("db.json", '[{"v":22}]');
  assert.deepEqual(JSON.parse(await new Router(db).getString("db.json")), [{ v: 22 }]);
  assert.deepEqual(db.data, [{ v: 22 }]);
  assert.equal(reloads, 1);
  assert.equal(db.isDirty(), false);
});

it("access keeps unsaved edits over an external edit; save then conflicts", async () => {
  env = await createTestProject("jsondb-refresh-dirty");
  await env.write("db.json", '[{"v":1}]');
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");
  db.data = [{ v: "mine" }];

  await env.write("db.json", '[{"v":"theirs"}]');
  assert.deepEqual(JSON.parse(await new Router(db).getString("db.json")), [{ v: "mine" }]);
  assert.deepEqual(db.data, [{ v: "mine" }]);
  await assert.rejects(db.save(), { code: "WHET_FILE_CONFLICT" });
});

it("reload: refuses with unsaved changes unless forced; fires listeners", async () => {
  env = await createTestProject("jsondb-reload");
  await env.write("db.json", '[{"v":1}]');
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");
  const seen = [];
  const off = db.onReload(() => seen.push(structuredClone(db.data)));

  db.data = [{ v: "unsaved" }];
  await env.write("db.json", '[{"v":2}]');
  await assert.rejects(db.reload(), { code: "WHET_UNSAVED_CHANGES" });
  assert.deepEqual(db.data, [{ v: "unsaved" }]);

  await db.reload(true);
  assert.deepEqual(db.data, [{ v: 2 }]);
  assert.deepEqual(seen, [[{ v: 2 }]]);
  assert.equal(await db.save(), false); // clean, in sync with disk: no conflict, nothing written

  off();
  await db.reload();
  assert.equal(seen.length, 1);
});

it("reload: a broken file or failing listener restores data and retries on next access", async () => {
  env = await createTestProject("jsondb-reload-broken");
  await env.write("db.json", '[{"v":1}]');
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");

  await env.write("db.json", '[{"v":'); // half-written
  await assert.rejects(db.getSource());
  assert.deepEqual(db.data, [{ v: 1 }]);
  await assert.rejects(db.getSource()); // still broken → still failing, not silently stale

  await env.write("db.json", '[{"v":3}]');
  let fail = true;
  db.onReload(() => {
    if (fail) throw new Error("listener failed");
  });
  await assert.rejects(db.refresh(), /listener failed/);
  assert.deepEqual(db.data, [{ v: 1 }]);

  fail = false;
  assert.equal(await db.refresh(), true);
  assert.deepEqual(db.data, [{ v: 3 }]);
});

it("save: disk changed to exactly the bytes being saved → no conflict, no write", async () => {
  env = await createTestProject("jsondb-same-bytes");
  await env.write("db.json", "[]");
  const db = new JsonDb({ project: env.project, id: "db.json" });
  await db.load("db.json");
  db.data = [{ v: 1 }];
  await env.write("db.json", JSON.stringify(db.data, null, "  ")); // someone made the same edit
  assert.equal(await db.save(), false);
  assert.equal(db.isDirty(), false);
  assert.equal(await db.diskChanged(), false);
});

it("load: missing file copies defaultData, so edits don't leak into the config", async () => {
  env = await createTestProject("jsondb-default-copy");
  const db = new JsonDb({ project: env.project, id: "db.json", defaultData: [{ v: 1 }] });
  await db.load("db.json");
  db.data.push({ v: 2 });
  assert.deepEqual(db.config.defaultData, [{ v: 1 }]);
  await db.reload(true);
  assert.deepEqual(db.data, [{ v: 1 }]);
});
