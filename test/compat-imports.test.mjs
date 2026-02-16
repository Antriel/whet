import test from "node:test";
import assert from "node:assert/strict";

import { Project, Router, JsonStone, Stone } from "../bin/whet.js";
import {
  CacheStrategy,
  CacheDurability,
  DurabilityCheck,
} from "../bin/whet/cache/Cache.js";
import { SourceData } from "../bin/whet/Source.js";

test("compat imports from top-level and deep paths resolve", () => {
  assert.equal(typeof Project, "function");
  assert.equal(typeof Router, "function");
  assert.equal(typeof JsonStone, "function");
  assert.equal(typeof Stone, "function");
  assert.equal(typeof SourceData.fromString, "function");

  assert.equal(typeof CacheStrategy.InMemory, "function");
  assert.equal(typeof CacheDurability.KeepForever, "object");
  assert.equal(typeof DurabilityCheck.AllOnUse, "object");
});

