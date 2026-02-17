import test from "node:test";
import assert from "node:assert/strict";

import { IdUtils } from "../bin/whet/SourceId.js";

test("IdUtils basic path transforms", () => {
  assert.equal(IdUtils.getWithExt("a/b/file.txt"), "file.txt");
  assert.equal(IdUtils.getWithoutExt("a/b/file.txt"), "file");
  assert.equal(IdUtils.getExt("a/b/file.txt"), ".txt");
  assert.equal(IdUtils.getDir("a/b/file.txt"), "a/b/");
  assert.equal(IdUtils.setWithExt("a/b/file.txt", "x.json"), "a/b/x.json");
  assert.equal(IdUtils.setWithoutExt("a/b/file.txt", "renamed"), "a/b/renamed.txt");
  assert.equal(IdUtils.setExt("a/b/file.txt", "json"), "a/b/file.json");
  assert.equal(IdUtils.setDir("a/b/file.txt", "c/d/"), "c/d/file.txt");
});

test("IdUtils directory checks and relative placement", () => {
  assert.equal(IdUtils.isDir("assets/"), true);
  assert.equal(IdUtils.isDir("assets"), false);
  assert.equal(IdUtils.isInDir("a/b/file.txt", "a/b/"), true);
  assert.equal(IdUtils.isInDir("a/b/c/file.txt", "a/b/", true), true);
  assert.equal(IdUtils.isInDir("x/file.txt", "a/b/", true), false);
  assert.equal(IdUtils.getRelativeTo("a/b/c/file.txt", "a/b/"), "c/file.txt");
  assert.equal(IdUtils.getRelativeTo("x/y.txt", "a/b/"), null);
  assert.equal(IdUtils.getPutInDir("file.txt", "a/b/"), "a/b/file.txt");
});

test("IdUtils normalize and cwd conversions", () => {
  assert.equal(IdUtils.normalize("a\\b\\c.txt"), "a/b/c.txt");
  assert.equal(IdUtils.normalize("./a//b/../c"), "a/c");
  assert.equal(IdUtils.toCwdPath("a/b.txt", "root/"), "root/a/b.txt");
});

test("IdUtils compare and assertDir behavior", () => {
  assert.equal(IdUtils.compare("a", "b"), -1);
  assert.equal(IdUtils.compare("b", "a"), 1);
  assert.equal(IdUtils.compare("x", "x"), 0);
  assert.throws(() => IdUtils.assertDir("not-a-dir"));
  assert.doesNotThrow(() => IdUtils.assertDir("is-a-dir/"));
});

