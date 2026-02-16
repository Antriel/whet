import test from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { stat, writeFile, utimes } from "node:fs/promises";

import { HashCache } from "../bin/whet/cache/HashCache.js";
import { SourceHash } from "../bin/whet/SourceHash.js";
import { createTestProject } from "./helpers/test-env.mjs";

test("HashCache.get returns singleton instance", () => {
  assert.equal(HashCache.get(), HashCache.get());
});

test("HashCache returns same hash for unchanged file", async () => {
  const env = await createTestProject("hash-cache-unchanged");
  const file = path.join(env.rootDir, "a.txt");
  await writeFile(file, "alpha");

  const cache = HashCache.get();
  const h1 = await cache.getFileHash(file);
  const h2 = await cache.getFileHash(file);
  assert.equal(h1.toString(), h2.toString());

  await env.cleanup();
});

test("HashCache rehashes when mtime changes", async () => {
  const env = await createTestProject("hash-cache-mtime-change");
  const file = path.join(env.rootDir, "a.txt");
  await writeFile(file, "alpha");

  const cache = HashCache.get();
  const h1 = await cache.getFileHash(file);
  await writeFile(file, "bravo"); // same length but different bytes
  const st = await stat(file);
  await utimes(file, st.atime, new Date(st.mtimeMs + 2000));
  const h2 = await cache.getFileHash(file);
  assert.notEqual(h1.toString(), h2.toString());

  await env.cleanup();
});

test("HashCache uses cached hash when mtime+size match", async () => {
  const env = await createTestProject("hash-cache-fast-path");
  const file = path.join(env.rootDir, "a.txt");
  await writeFile(file, "aaaa");
  const cache = HashCache.get();

  const st = await stat(file);
  const fake = SourceHash.fromString("forced-cached-value");
  cache.cache.inst.set(file, {
    mtime: st.mtimeMs,
    size: st.size,
    hash: fake.toString(),
  });

  const got = await cache.getFileHash(file);
  assert.equal(got.toString(), fake.toString());
  await env.cleanup();
});

test("HashCache rejects missing files and getStats returns mtime+size", async () => {
  const env = await createTestProject("hash-cache-errors");
  const file = path.join(env.rootDir, "a.txt");
  await writeFile(file, "x");
  const stats = await HashCache.getStats(file);
  assert.equal(typeof stats.mtime, "number");
  assert.equal(typeof stats.size, "number");

  await assert.rejects(() => HashCache.get().getFileHash(path.join(env.rootDir, "missing.txt")));
  await env.cleanup();
});
