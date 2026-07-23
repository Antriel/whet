---
# whet-uzjf
title: 'configSchema(): per-class config schemas, stone-schema CLI, StoneStore validation'
status: todo
type: feature
created_at: 2026-07-23T07:08:07Z
updated_at: 2026-07-23T07:08:07Z
parent: whet-1vzf
blocked_by:
    - whet-hnde
---

The "keystone" from doc 03: optional per-stone-class config schemas, surfaced to the registry, a `whet stone-schema <type>` CLI (doc 04 §5), and StoneStore sync-time validation. Gives dead `StoneConfigMeta.uiHints` (doc 02 §4) its purpose. Editor form generation is scry-app work, out of scope here.

## Frozen decisions

- **Format: standard JSON Schema (draft-07 subset)** describing the stone's *editable config object* (the JSON-serializable fields — the same set `Project.getStoneConfig` puts in `editable`). Fields that hold stones/routers may be described as `{"type": "object"}` or omitted. Standard JSON Schema so scry-app's Monaco integration (which already consumes JSON schemas) can use it directly later.
- **Convention**: `static configSchema()` — a static *function* returning the schema object. JS stones: `static configSchema() { return {...}; }`. Haxe stones: `@:keep public static function configSchema():Dynamic`.
- `StoneRegistry.register` already reads `ctor.configSchema?.()` (hook wired in whet-hnde); `registerBuilder` takes schema explicitly.
- **No external validator dependency** (no ajv — whet keeps deps minimal). Write `src/whet/stones/SchemaValidator.hx`: `validate(value:Dynamic, schema:Dynamic, ?path:String):Array<{path:String, message:String}>` supporting exactly: `type` (string or array), `properties`, `required`, `additionalProperties` (boolean only), `items`, `enum`, `minimum`, `maximum`, `minLength`, `pattern`; `description`/`default` ignored. Unknown keywords ignored (forward-compat). **Skip validation of any subtree whose value is a single-key `{$stone: ...}` or `{$router: ...}` object** — those revive to live instances and legitimately mismatch the schema.
- **StoneStore integration**: in `syncEntries` validation (whet-31lx step 1), when the registry entry for a flat entry's type has a schema, run the validator on the entry's config (post-expansion, post-token-substitution, pre-revive) and add any findings (with `entryKey + path`) to the aggregated all-or-nothing error.
- **CLI**: `whet stone-schema <type>` — a core command registered next to the existing `schema` command (see how `schema` is implemented/registered in `src/whet/Whet.hx` from the whet-hqwq work, and follow its stdout/NDJSON conventions). With a known type: print the schema JSON (or a clear "type has no schema" message, exit 0). Unknown type: list registered type names, exit 1. No arg: print `StoneRegistry.list()`.
- **Project.getStoneConfig**: populate `meta.uiHints` with the schema for the stone's class when one is registered/available (lookup by constructor via the registry, or read `constructor.configSchema` directly off the instance — the latter also covers unregistered classes; prefer it).
- Add a reference `configSchema()` to one built-in (`JsonDb` — trivial) and to test/helpers/mock-stone.mjs's MockStone for tests.

## Todos

- [ ] SchemaValidator with per-keyword unit tests (`test/schema-validator.test.mjs`), incl. $stone/$router skip and path-prefixed messages
- [ ] configSchema convention: MockStone + JsonDb reference schemas; registry pickup verified
- [ ] StoneStore sync validation integration + test (bad entry config → aggregated error naming entry key + JSON path; stones untouched)
- [ ] `whet stone-schema` command + smoke test (check test/ for an existing CLI spawn pattern; if none exists, cover the command's handler function directly and note manual CLI verification)
- [ ] getStoneConfig meta.uiHints wiring + test
- [ ] Rebuild + full test run green
