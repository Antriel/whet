import { it } from "node:test";
import assert from "node:assert/strict";
import { SchemaValidator } from "../bin/whet.js";

// Small helper: assert value is valid (no findings) against schema.
function ok(value, schema) {
  const findings = SchemaValidator.validate(value, schema);
  assert.deepEqual(findings, [], `expected no findings, got: ${JSON.stringify(findings)}`);
}

// Small helper: assert value produces at least one finding whose path/message match.
function bad(value, schema, { path, message } = {}) {
  const findings = SchemaValidator.validate(value, schema);
  assert.ok(findings.length > 0, "expected at least one finding");
  if (path !== undefined)
    assert.ok(findings.some((f) => f.path === path), `expected a finding at path "${path}": ${JSON.stringify(findings)}`);
  if (message !== undefined)
    assert.ok(findings.some((f) => f.message.includes(message)), `expected a finding matching "${message}": ${JSON.stringify(findings)}`);
  return findings;
}

// --- type ---

it("type: scalar types accept/reject", () => {
  ok("hi", { type: "string" });
  ok(3, { type: "number" });
  ok(true, { type: "boolean" });
  ok([], { type: "array" });
  ok({}, { type: "object" });
  ok(null, { type: "null" });
  bad(3, { type: "string" }, { path: "", message: "expected type string, got number" });
  bad("x", { type: "number" }, { message: "got string" });
});

it("type: integer distinguishes from float", () => {
  ok(4, { type: "integer" });
  bad(4.5, { type: "integer" }, { message: "expected type integer" });
});

it("type: array of allowed types", () => {
  ok("x", { type: ["string", "null"] });
  ok(null, { type: ["string", "null"] });
  bad(3, { type: ["string", "null"] }, { message: "string or null" });
});

it("type mismatch short-circuits deeper checks (no noise)", () => {
  const findings = SchemaValidator.validate("nope", { type: "object", required: ["a"] });
  assert.equal(findings.length, 1);
  assert.ok(findings[0].message.includes("expected type object"));
});

// --- properties / required / additionalProperties ---

it("required: flags missing properties by name", () => {
  const schema = { type: "object", required: ["id", "content"], properties: {} };
  bad({ id: "x" }, schema, { path: "", message: 'missing required property "content"' });
  ok({ id: "x", content: "y" }, schema);
});

it("properties: recurses with dotted paths", () => {
  const schema = {
    type: "object",
    properties: { nested: { type: "object", properties: { n: { type: "number" } } } },
  };
  bad({ nested: { n: "notnum" } }, schema, { path: "nested.n", message: "expected type number" });
});

it("additionalProperties:false flags unknown keys (permissive when omitted)", () => {
  const schema = { type: "object", properties: { a: { type: "string" } } };
  ok({ a: "x", extra: 123 }, schema); // omitted → permissive
  const strict = { ...schema, additionalProperties: false };
  bad({ a: "x", extra: 123 }, strict, { path: "extra", message: 'additional property "extra" is not allowed' });
});

// --- items ---

it("items: validates each element with indexed path", () => {
  const schema = { type: "array", items: { type: "object", properties: { id: { type: "string" } }, required: ["id"] } };
  ok([{ id: "a" }, { id: "b" }], schema);
  bad([{ id: "a" }, { nope: 1 }], schema, { path: "[1]", message: 'missing required property "id"' });
  bad([{ id: 5 }], schema, { path: "[0].id", message: "expected type string" });
});

// --- enum ---

it("enum: membership by strict equality", () => {
  ok("png", { enum: ["png", "webp"] });
  bad("gif", { enum: ["png", "webp"] }, { message: "not one of the allowed values" });
  ok(2, { enum: [1, 2, 3] });
  bad(4, { enum: [1, 2, 3] });
});

// --- numeric bounds ---

it("minimum / maximum", () => {
  ok(5, { type: "number", minimum: 0, maximum: 10 });
  bad(-1, { type: "number", minimum: 0 }, { message: "below minimum" });
  bad(11, { type: "number", maximum: 10 }, { message: "above maximum" });
});

// --- string constraints ---

it("minLength", () => {
  ok("ab", { type: "string", minLength: 2 });
  bad("a", { type: "string", minLength: 2 }, { message: "below minLength" });
});

it("pattern", () => {
  ok("abc123", { type: "string", pattern: "^[a-z0-9]+$" });
  bad("ABC", { type: "string", pattern: "^[a-z]+$" }, { message: "does not match pattern" });
});

// --- $stone / $router skip ---

it("skips $stone sentinel subtrees (revive to live instances)", () => {
  // A property declared as an object but holding a {$stone} ref must not be flagged.
  const schema = { type: "object", properties: { src: { type: "object", required: ["path"] } } };
  ok({ src: { $stone: "some-id" } }, schema);
  ok({ src: { $router: [["/", "assets/"]] } }, schema);
  // But an extra key alongside $stone is NOT a sentinel → validated normally.
  bad({ src: { $stone: "x", extra: 1 } }, schema, { path: "src", message: 'missing required property "path"' });
});

it("skips a top-level $router value", () => {
  ok({ $router: [["/", "assets/"]] }, { type: "object", required: ["mustHave"] });
});

// --- unknown keywords ignored (forward-compat) ---

it("ignores unknown keywords and description/default", () => {
  ok("x", { type: "string", description: "hi", default: "d", futureKeyword: 42 });
});

it("empty schema / non-object schema → no findings", () => {
  ok({ anything: 1 }, {});
  ok("x", null);
  ok("x", true);
});
