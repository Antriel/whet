import test from "node:test";
import assert from "node:assert/strict";

import { OutputFilterMatcher } from "../bin/whet/route/OutputFilterMatcher.js";

test("OutputFilterMatcher returns true for null filter", () => {
  assert.equal(OutputFilterMatcher.couldMatch("assets/a.txt", null, false), true);
});

test("OutputFilterMatcher extension filtering supports compound extensions", () => {
  const filter = { extensions: ["json", "meta.json"], patterns: null };
  assert.equal(OutputFilterMatcher.couldMatch("a/b/file.png.meta.json", filter, false), true);
  assert.equal(OutputFilterMatcher.couldMatch("a/b/file.txt", filter, false), false);
});

test("OutputFilterMatcher pattern filtering applies for non-wildcard queries", () => {
  const filter = { extensions: null, patterns: ["assets/**/*.png", "icon.svg"] };
  assert.equal(OutputFilterMatcher.couldMatch("x/assets/ui/a.png", filter, false), true);
  assert.equal(OutputFilterMatcher.couldMatch("icon.svg", filter, false), true);
  assert.equal(OutputFilterMatcher.couldMatch("assets/ui/a.jpg", filter, false), false);
});

test("OutputFilterMatcher wildcard queries are treated conservatively", () => {
  const filter = { extensions: null, patterns: ["assets/**/*.png"] };
  assert.equal(OutputFilterMatcher.couldMatch("assets/**", filter, true), true);
});

test("OutputFilterMatcher queries without extension cannot be rejected by extension filter", () => {
  const filter = { extensions: ["png"], patterns: null };
  assert.equal(OutputFilterMatcher.couldMatch("assets/**", filter, true), true);
});

