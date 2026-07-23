import { it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { stat } from "node:fs/promises";
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
