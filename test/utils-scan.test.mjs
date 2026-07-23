import { it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { Utils } from "../bin/whet.js";
import { createTestProject } from "./helpers/test-env.mjs";

let env;
afterEach(async () => {
  if (env) await env.cleanup();
  env = null;
});

it("scanFiles walks nested dirs, returning project-relative posix paths sorted by path", async () => {
  env = await createTestProject("scan-nested");
  await env.write("assets/a.wav", "x");
  await env.write("assets/sub/b.wav", "x");
  await env.write("assets/sub/deep/c.wav", "x");
  await env.write("assets/note.txt", "x"); // excluded by the pattern

  const { files, names } = await Utils.scanFiles(env.rootDir, "assets/", "(.*)\\.wav$");
  assert.deepEqual(files, ["assets/a.wav", "assets/sub/b.wav", "assets/sub/deep/c.wav"]);
  // `$1` capture is the full path relative to the scan dir (minus `.wav`).
  assert.deepEqual(names, ["a", "sub/b", "sub/deep/c"]);
});

it("scanFiles skips dot-directories and node_modules", async () => {
  env = await createTestProject("scan-skip");
  await env.write("assets/keep.wav", "x");
  await env.write("assets/.hidden/skip.wav", "x");
  await env.write("assets/node_modules/skip.wav", "x");

  // `dir` without a trailing slash is normalized the same as with one.
  const { files } = await Utils.scanFiles(env.rootDir, "assets", "\\.wav$");
  assert.deepEqual(files, ["assets/keep.wav"]);
});

it("scanFiles applies nameTemplate captures and falls back to the file stem", async () => {
  env = await createTestProject("scan-names");
  await env.write("sfx/punch_01.wav", "x");
  await env.write("sfx/kick.wav", "x");

  // A capturing template keeps only the matching file and derives the name from the capture.
  const withCap = await Utils.scanFiles(env.rootDir, "sfx/", "(.*)_\\d+\\.wav$", "$1");
  assert.deepEqual(withCap.files, ["sfx/punch_01.wav"]);
  assert.deepEqual(withCap.names, ["punch"]);

  // A pattern with no capture group → name falls back to the file stem.
  const noCap = await Utils.scanFiles(env.rootDir, "sfx/", "\\.wav$");
  assert.deepEqual(noCap.files, ["sfx/kick.wav", "sfx/punch_01.wav"]);
  assert.deepEqual(noCap.names, ["kick", "punch_01"]);
});

it("scanFiles supports a literal-prefixed nameTemplate", async () => {
  env = await createTestProject("scan-template");
  await env.write("f/one.dat", "x");

  const { names } = await Utils.scanFiles(env.rootDir, "f/", "(.*)\\.dat$", "sfx_$1");
  assert.deepEqual(names, ["sfx_one"]);
});
