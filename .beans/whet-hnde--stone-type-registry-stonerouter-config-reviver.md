---
# whet-hnde
title: Stone-type registry + $stone/$router config reviver
status: todo
type: feature
created_at: 2026-07-23T07:06:27Z
updated_at: 2026-07-23T07:06:27Z
parent: whet-1vzf
---

The two standalone pieces StoneStore needs (doc 03 pieces 1–2): a registry mapping type names to entry **builders**, and a reviver turning JSON configs into live configs. Small, isolated, fully testable without StoneStore.

Files: `src/whet/stones/StoneRegistry.hx`, `src/whet/stones/ConfigReviver.hx`. Both must be reachable from JS imports of bin/whet.js (`@:expose`; check build.hxml exposure setup and verify with a test import). See epic whet-1vzf for conventions.

## StoneRegistry (class with static API)

Typedefs:
- `BuiltEntry = FactoryEntry & { ?mainStone:AnyStone, ?update:(key:String, revivedConfig:Dynamic, existing:Dynamic)->Void }` (FactoryEntry is `{stones, ?routes}` from StoneFactory.hx)
- `StoneBuilder = (key:String, revivedConfig:Dynamic) -> BuiltEntry`
- `StoneTypeEntry = { name:String, builder:StoneBuilder, ?schema:Dynamic }`

API (all `@:keep`):
- `register(name:String, ctor:Dynamic, ?schema:Dynamic):Void` — single-stone sugar. Wraps into a builder that instantiates `new ctor({...config, id: key})` (via `js.Syntax.code("new {0}({1})", ctor, cfg)`; shallow-copy config and set id — do not mutate the caller's object) and returns `{stones:[s], mainStone:s}`. When `schema` omitted, read `ctor.configSchema` if it is a function and call it (safe via js.Syntax; configSchema convention lands in a sibling bean — just wire the hook now).
- `registerBuilder(name:String, builder:StoneBuilder, ?schema:Dynamic):Void` — raw form for composite chains (a future AudioDb-style type builds its whole wav→sox→…→ogg chain here, and can conditionally skip stages — the "SoX-optional skip-stone" pattern). Builders return their own `routes`; `mainStone` optional.
- `get(name:String):Null<StoneTypeEntry>`, `list():Array<{name:String, hasSchema:Bool}>`.
- Duplicate name: `Log.warn` + overwrite (dev-friendly re-imports).
- Whet registers built-ins at startup (one-liners, e.g. in Whet.hx init or a small static init called from there): `Files`, `JsonStone`, `Zip`, `RemoteFile` (+ `JsonDb` once the sibling bean lands). Skip HaxeBuild/Hxml for now.

## ConfigReviver

- `revive(value:Dynamic, resolve:(id:String)->AnyStone):Dynamic` — recursive deep transform producing a new value (never mutates input):
  - plain object whose only key is `"$stone"` (string value) → `resolve(id)`. `resolve` throws with the id in the message when unknown — the caller owns lookup policy.
  - plain object whose only key is `"$router"` → `new Router(revive($router value))` — route arrays are revived recursively so nested `{$stone}` objects become live stones; **plain strings pass through unchanged** (RoutePathType already treats a string as a `Files` path shortcut — keep that behavior).
  - arrays → element-wise revive; plain objects → new object with revived values; primitives → as-is.
  - Objects that have `$stone`/`$router` alongside other keys: throw a clear error (malformed ref).
- `collectStoneRefs(value:Dynamic):Array<String>` — recursively collect all `$stone` id strings in a JSON value, deduped, order of first appearance. Used by StoneStore for topo sort and the update cascade.
- Implementation style: mirror `ConfigStore.deepClone`'s walking (DynamicAccess iteration; plain-object check like `ConfigStore.isJsonSerializable`).

## Todos

- [ ] StoneRegistry with register/registerBuilder/get/list + built-in registrations
- [ ] ConfigReviver revive + collectStoneRefs
- [ ] Tests `test/stone-registry.test.mjs`: register a MockStone type and build via sugar (stone id == key, config passed through); registerBuilder composite returning 2 stones + routes; duplicate registration warns and overwrites; list() shape
- [ ] Tests `test/config-reviver.test.mjs` (can share file): revive nested $stone (resolve called with id, live object substituted); revive $router with mixed string + {$stone} routes yields a working Router (get() serves the stone's output); unknown $stone error contains the id; malformed ref (extra keys) throws; collectStoneRefs finds refs at any depth incl. inside $router, deduped; input object not mutated
- [ ] Rebuild + full test run green
