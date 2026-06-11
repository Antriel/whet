import test from "node:test";
import assert from "node:assert/strict";

import { Stone, Project } from "../bin/whet.js";
import { SourceData } from "../bin/whet/Source.js";
import { SourceHash } from "../bin/whet/SourceHash.js";
import {
  CacheStrategy,
  CacheDurability,
  DurabilityCheck,
} from "../bin/whet/cache/Cache.js";
import { createTestProject } from "./helpers/test-env.mjs";

// --- Stones that override generateHash() (the optimization path). Their covered-method *source
// text* now participates in the hash via Stone.codeHash, so editing generation logic busts caches.

class StoneA extends Stone {
  async generateHash() { return SourceHash.fromString("stable"); }
  async generate() { return [SourceData.fromString("out.txt", "out")]; }
}

// Byte-identical generate()/generateHash() source to StoneA.
class StoneAClone extends Stone {
  async generateHash() { return SourceHash.fromString("stable"); }
  async generate() { return [SourceData.fromString("out.txt", "out")]; }
}

// Same generate()/generateHash() as StoneA, plus a private helper method. All own methods
// participate in the hash, so this must differ from StoneA.
class StoneAExtra extends Stone {
  async generateHash() { return SourceHash.fromString("stable"); }
  async generate() { return [SourceData.fromString("out.txt", "out")]; }
  helper() { return 7; }
}

// Different generate() body (a covered method) — simulates editing generation logic.
class StoneB extends Stone {
  async generateHash() { return SourceHash.fromString("stable"); }
  async generate() { return [SourceData.fromString("out.txt", "out")]; /* edited */ }
}

// --- Stones WITHOUT generateHash() (byte-hash path). Code is NOT mixed in here; their output
// bytes already reflect generate() changes.

class NoHashA extends Stone {
  async generate() { return [SourceData.fromString("o.txt", "same")]; }
}
class NoHashB extends Stone {
  async generate() { return [SourceData.fromString("o.txt", "same")]; /* different source */ }
}

test("code hash: identical covered-method source produces identical hash", async () => {
  const env = await createTestProject("codehash-identical");
  const a = new StoneA({ project: env.project, id: "a" });
  const clone = new StoneAClone({ project: env.project, id: "clone" });
  assert.equal((await a.getHash()).toString(), (await clone.getHash()).toString());
  await env.cleanup();
});

test("code hash: a private helper method participates in the hash", async () => {
  const env = await createTestProject("codehash-helper");
  const a = new StoneA({ project: env.project, id: "a" });
  const extra = new StoneAExtra({ project: env.project, id: "extra" });
  // Editing/adding any own method (here a helper not called by generate in the test, but it could be)
  // busts the hash — closing the gap where a `this.helper()` edit left cached output stale.
  assert.notEqual((await a.getHash()).toString(), (await extra.getHash()).toString());
  await env.cleanup();
});

test("code hash: a static helper method participates in the hash", async () => {
  const env = await createTestProject("codehash-static");
  class WithStatic extends Stone {
    static build() { return "x"; }
    async generateHash() { return SourceHash.fromString("stable"); }
    async generate() { return [SourceData.fromString("out.txt", "out")]; }
  }
  const a = new StoneA({ project: env.project, id: "a" });
  const s = new WithStatic({ project: env.project, id: "s" });
  assert.notEqual((await a.getHash()).toString(), (await s.getHash()).toString());
  await env.cleanup();
});

test("code hash: editing a covered method body busts the hash", async () => {
  const env = await createTestProject("codehash-bust");
  const a = new StoneA({ project: env.project, id: "a" });
  const b = new StoneB({ project: env.project, id: "b" });
  assert.notEqual((await a.getHash()).toString(), (await b.getHash()).toString());
  await env.cleanup();
});

test("code hash: ignoreCodeHash opts out, restoring config-only hashing", async () => {
  const env = await createTestProject("codehash-optout");
  const a = new StoneA({ project: env.project, id: "a" });
  const b = new StoneB({ project: env.project, id: "b" });
  a.ignoreCodeHash = true;
  b.ignoreCodeHash = true;
  // With code excluded, both depend only on the identical generateHash() result.
  assert.equal((await a.getHash()).toString(), (await b.getHash()).toString());
  await env.cleanup();
});

test("code hash: not mixed in for stones without generateHash()", async () => {
  const env = await createTestProject("codehash-bytepath");
  const a = new NoHashA({ project: env.project, id: "a" });
  const b = new NoHashB({ project: env.project, id: "b" });
  // Different generate() source but identical output bytes → identical byte hash (code not mixed in).
  assert.equal((await a.getHash()).toString(), (await b.getHash()).toString());
  await env.cleanup();
});

// --- End-to-end: prove the feature's actual purpose (no more stale cached output) by round-tripping
// through a persistent file cache across two "builds". Two sibling classes with the same stone id and
// the same generateHash() model the same stone before and after a code edit (a real edit = recompile +
// new process, so a separate class with a fresh constructor is the faithful model, and the per-class
// codeHash memo is naturally cold). Without the code hash, "build 2" would silently serve build 1's
// stale bytes — these tests fail in exactly that way if codeHash is removed.

const FILE_STRATEGY = () =>
  CacheStrategy.InFile(CacheDurability.KeepForever, DurabilityCheck.AllOnUse);

// "Build 1" stone: a stable generateHash(), counts generations, emits a marker.
class BuildV1 extends Stone {
  async generateHash() { return SourceHash.fromString("same-config"); }
  async generate() { this.count = (this.count ?? 0) + 1; return [SourceData.fromString("o.txt", "v1-bytes")]; }
}
// "Build 2" — byte-identical generate()/generateHash() source to BuildV1 (no code change).
class BuildV1Clone extends Stone {
  async generateHash() { return SourceHash.fromString("same-config"); }
  async generate() { this.count = (this.count ?? 0) + 1; return [SourceData.fromString("o.txt", "v1-bytes")]; }
}
// "Build 2" — edited generate() body and different output, same config/hashKey.
class BuildV2 extends Stone {
  async generateHash() { return SourceHash.fromString("same-config"); }
  async generate() { this.count = (this.count ?? 0) + 1; return [SourceData.fromString("o.txt", "v2-bytes")]; /* edited */ }
}

async function buildOne(rootDir) {
  const project = new Project({ name: "whet-codehash-b1", id: `whet-codehash-b1-${Math.random()}`, rootDir });
  const s = new BuildV1({ project, id: "shared", cacheStrategy: FILE_STRATEGY() });
  await s.getSource();
  assert.equal(s.count, 1); // generated and persisted to the file cache
  await project.cache.close();
}

test("code hash (e2e): editing generate() makes a new build miss the file cache and regenerate", async () => {
  const env = await createTestProject("codehash-e2e-bust");
  await buildOne(env.rootDir);

  // Build 2 with edited code, same id + same cache dir.
  const p2 = new Project({ name: "whet-codehash-b2", id: `whet-codehash-b2-${Math.random()}`, rootDir: env.rootDir });
  const s2 = new BuildV2({ project: p2, id: "shared", cacheStrategy: FILE_STRATEGY() });
  const src = await s2.getSource();

  assert.equal(s2.count, 1); // regenerated rather than serving build 1's cached bytes
  assert.equal(src.get().data.toString("utf-8"), "v2-bytes"); // fresh output, not stale "v1-bytes"
  await env.cleanup();
});

test("code hash (e2e): identical code still reuses the file cache (no needless rebuild)", async () => {
  const env = await createTestProject("codehash-e2e-reuse");
  await buildOne(env.rootDir);

  // Build 2 with byte-identical code, same id + same cache dir.
  const p2 = new Project({ name: "whet-codehash-b2", id: `whet-codehash-b2-${Math.random()}`, rootDir: env.rootDir });
  const s2 = new BuildV1Clone({ project: p2, id: "shared", cacheStrategy: FILE_STRATEGY() });
  const src = await s2.getSource();

  assert.equal(s2.count ?? 0, 0); // served from cache, never regenerated
  assert.equal(src.get().data.toString("utf-8"), "v1-bytes");
  await env.cleanup();
});
