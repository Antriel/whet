import { it, afterEach } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { stat, writeFile, utimes } from "node:fs/promises";
import { TrackedFile } from "../bin/whet/TrackedFile.js";
import { createTestProject } from "./helpers/test-env.mjs";
import { holdRenames, deferNext, countCalls } from "./helpers/fs-hold.mjs";

let env;
afterEach(async () => {
  if (env) await env.cleanup();
  env = null;
});

it("changed() that overlapped our own write re-checks after it instead of reporting a change", async () => {
  env = await createTestProject("tracked-overlap");
  await env.write("f.txt", "a");
  const file = new TrackedFile(path.join(env.rootDir, "f.txt"));
  await file.read();

  // changed() starts before the write, but its stat only lands after the rename.
  const stat = deferNext("stat");
  const hold = holdRenames();
  try {
    const checking = file.changed();
    await stat.called;
    const writing = file.write("bbb");
    await hold.renamed();
    stat.run(); // sees the new size against the old recorded state
    await new Promise((r) => setTimeout(r, 20));
    hold.release();
    assert.equal(await writing, true);
    assert.equal(await checking, false);
  } finally {
    stat.restore();
    stat.run();
    hold.release();
  }
  assert.equal(await file.changed(), false);
});

it("read() during a write resolves with the written content", async () => {
  env = await createTestProject("tracked-read-mid-write");
  await env.write("f.txt", "a");
  const file = new TrackedFile(path.join(env.rootDir, "f.txt"));
  await file.read();

  const hold = holdRenames();
  let reading;
  try {
    const writing = file.write("bbb");
    await hold.renamed();
    reading = file.read();
    hold.release();
    await writing;
  } finally {
    hold.release();
  }
  assert.equal(await reading, "bbb");
  assert.equal(await file.changed(), false);
});

// --- Racy mtimes: a same-size write within the mtime granularity keeps the mtime ---

it("a same-size edit that kept the mtime of a fresh read is still detected", async () => {
  env = await createTestProject("tracked-racy");
  const file = path.join(env.rootDir, "f.json");
  // Pin both writes to one whole-ms mtime (utimes rounds sub-ms values), as if they shared a tick.
  const tick = Math.floor(Date.now()) / 1000;
  await writeFile(file, '{"v":1}');
  await utimes(file, tick, tick);
  const tracked = new TrackedFile(file);
  await tracked.read();

  await writeFile(file, '{"v":5}');
  await utimes(file, tick, tick);
  assert.equal((await stat(file)).mtimeMs, tick * 1000);
  assert.equal(await tracked.changed(), true);
});

it("a state confirmed well after the mtime is trusted on stat alone", async () => {
  env = await createTestProject("tracked-settled");
  const file = path.join(env.rootDir, "f.json");
  await writeFile(file, '{"v":1}');
  const hourAgo = Date.now() / 1000 - 3600;
  await utimes(file, hourAgo, hourAgo);
  const tracked = new TrackedFile(file);
  await tracked.read();

  const reads = countCalls("readFile");
  try {
    assert.equal(await tracked.changed(), false);
  } finally {
    reads.restore();
  }
  assert.equal(reads.count, 0);
});

it("a racy state hashes until a check confirms it after the window", async () => {
  env = await createTestProject("tracked-racy-settles");
  const file = path.join(env.rootDir, "f.json");
  await writeFile(file, '{"v":1}');
  const tracked = new TrackedFile(file);
  await tracked.read();

  const realNow = Date.now;
  const reads = countCalls("readFile");
  try {
    assert.equal(await tracked.changed(), false);
    assert.equal(reads.count, 1); // fresh mtime: hashed

    Date.now = () => realNow() + 5000; // past the window
    assert.equal(await tracked.changed(), false);
    assert.equal(reads.count, 2); // still recorded as racy: hashed once more, now confirmed
    assert.equal(await tracked.changed(), false);
    assert.equal(reads.count, 2); // trusted on stat alone
  } finally {
    Date.now = realNow;
    reads.restore();
  }
});
