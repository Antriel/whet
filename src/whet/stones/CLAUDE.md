# Data-driven stones: implementation notes

User-facing entry format, references and `each` syntax: `docs/stone-store.md`. This file covers the
invariants to keep when changing the code.

## Layers (lowest to highest)

- **`StoneFactory<D, E>`** — *extends `Router`*, so a factory is a route source. `sync(data, keyFn)`
  diffs data against current entries: new → `createEntry`, changed → `updateEntry`, absent → removed
  (stones deregistered); returns removed keys for cache cleanup. Subclasses override `createEntry` /
  `updateEntry` / `addBaseRoutes`.
- **`StoneRegistry`** — named registry of *builders*: `(key, revivedConfig) -> {stones, routes?,
  mainStone?, update?}`, so one entry can declare a multi-stone chain. `register(name, ctor)` is
  single-stone sugar over `registerBuilder`. Built-ins self-register on first access. A static
  `configSchema()` on the class becomes the type's schema.
- **`StoneStore`** — a `StoneFactory` over JSON entries in a `JsonDb`. `ConfigReviver` resolves
  `$stone` / `$router` sentinels; `SchemaValidator` checks configs.

## `syncEntries()` invariants

- Validate everything before touching any stone; aggregate all findings into one path-specific error.
- Topologically sort by `$stone` refs; a cycle throws naming the path.
- Force-update dependents of any touched entry, so no unchanged entry keeps a dead instance of a
  recreated dependency. Default update is id-stable destroy+recreate (same id + config → same cache
  keys, so cache-neutral); a builder's `update` hook can mutate in place instead.
- `each` directory scans run **only** in `syncEntries()`, never in `previewEntry` (perf invariant).
  `getExpansion(groupId)` exposes the last scan for editor tooling.

## Preview / revert

`StoneFactory` keeps a canonical `dataMap` (last-synced data per key). `previewEntry(key, data)`
mutates the live stones without recording canonical state and forces no regeneration — changed
configs change hashes, so the hash cache regenerates lazily on next `getSource()`. `revertEntry(key)`
re-applies the `dataMap` entry (or removes a preview-created key). A completed `sync()` reasserts
canonical state over any lingering previews. `StoneStore` adds the dependent cascade + route rebuild
so previews stay reference-consistent. This backs live editing of unsaved configs in the editor —
no DB coupling, no baseline snapshot.

## Hashing and cache

A factory's hash is plain `Router.getHash()`: per-route static structure bound to each route's source
hash, merged order-independently — no id enumeration, so member stones without `list()` aren't forced
to generate. No extra self-hash. `Project.removeStone` deliberately doesn't clear cache; `StoneStore`
does it only with `clearCacheOnRemove: true`.
