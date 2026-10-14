# Overview

Whet is a NodeJS-based tool for managing project assets and tooling using a flexible "everything-is-an-asset" approach with configurable caching. It's written in Haxe and compiles to JavaScript (ES6 modules).

# Build Commands

- **Build the project**: `haxe build.hxml` (compiles Haxe to JavaScript, no output on success build)
- **Run a project**: `node bin/whet.js -p <project-file>` (default: `Project.mjs`)

The compiled output is `bin/whet.js` which serves as both the CLI entry point and importable library.

# Technology Stack

- **Language**: Haxe 4.3.4 (configured in `.haxerc`)
- **Target**: JavaScript ES6 modules (`-D js-es=6` in build.hxml)
- **Runtime**: Node.js
- **Key Libraries**:
  - `hxnodejs`: Node.js bindings for Haxe
  - `commander`: CLI argument parsing
  - `pino-pretty`: Logging
  - `minimatch`: Glob pattern matching

# Architecture

## Core Concepts

**Stones** are the fundamental building blocks. Each Stone represents a logical asset or functionality (e.g., a minified CSS file, a dev server). Stones can depend on other Stones, forming a dependency tree. All state is kept in a `config` object.

**Project** is the top-level container that holds Stones and commands. Projects are instantiated in `Project.mjs` files (or custom project files).

**Router** manages routing between Stones and file paths using glob patterns. Routes can filter, rename, and reorganize assets from Stones.

**Source** represents the generated output of a Stone. It contains one or more `SourceData` entries (each with a Buffer and SourceId).

**SourceHash** provides SHA-256 content hashing for caching and change detection. Hashes can be merged and combined to track dependencies.

**CacheManager** handles caching strategies (in-memory, file-based, or none) with configurable durability rules (by age, count, last use).

## Source Files Structure

- `src/whet/Whet.hx`: CLI entry point and command execution
- `src/whet/Project.hx`: Project container and command registration
- `src/whet/Stone.hx`: Abstract base class for all Stones
- `src/whet/route/Router.hx`: Asset routing and filtering
- `src/whet/Source.hx`: Generated asset data and file operations
- `src/whet/SourceHash.hx`: Content hashing utilities
- `src/whet/cache/`: Caching infrastructure (CacheManager, FileCache, MemoryCache)
- `src/whet/stones/`: Built-in Stone implementations (Files, JsonStone, RemoteFile, Zip, HaxeBuild, JsonDb) plus the data-driven layer (StoneFactory, StoneStore, StoneRegistry, ConfigReviver, SchemaValidator)
- `src/whet/magic/`: Type system abstractions (StoneId, MaybeArray, RoutePathType, MinimatchType)
- `externs/`: TypeScript definition conversions for Node.js libraries

## Key Design Patterns

1. **Everything-is-an-asset**: All project resources (files, builds, configurations) are treated as Stones
2. **Lazy generation**: Sources are only generated when needed and go through caching
3. **Hash-based caching**: Content hashing determines if regeneration is needed
4. **Lock acquisition**: Stones use `acquire()` to prevent parallel generation of the same resource
5. **Promise-based**: All async operations use Promises for consistency

## Path Conventions

- All paths use `/` as separator (cross-platform)
- Paths are relative to project root
- Directory paths end with `/` (e.g., `assets/` is a directory, `assets` is a file)
- `SourceId` is a abstract type over string for type safe and performance optimized id/relative paths handling

## Command Chaining

Commands can be chained with `+`:
```bash
node bin/whet.js -p Project.mjs command1 + command2
```

# Creating New Stones

Extend the abstract `Stone<T>` class:

1. Override `initConfig()` to set defaults
2. Override `addCommands()` to register CLI commands
3. Implement `generate(hash:SourceHash)` to create the asset
4. Optionally override `generateHash()` for optimization (to avoid generating sources just for hashing)

Stones automatically:
- Track dependencies via `config.dependencies`
- Handle caching based on `cacheStrategy`
- Merge dependency hashes into their own hash
- Lock during generation to prevent race conditions

# Data-Driven Stones

Beyond hand-wiring stones in a Project file, whet has a layer where a data file decides *which*
stones exist and how they connect. Three classes, lowest to highest level:

- **`StoneFactory<D, E>`** (`src/whet/stones/StoneFactory.hx`) — the base lifecycle. It *extends
  `Router`*, so a factory drops straight into routes as a source. `sync(data, keyFn)` diffs incoming
  data against the current entry set: new keys → `createEntry`, changed keys → `updateEntry`, absent
  keys → removed (their stones deregistered from the project); it returns the removed keys for cache
  cleanup. Subclasses override `createEntry` / `updateEntry` / `addBaseRoutes`. It also owns
  **preview/revert** (below) via a retained canonical `dataMap`.
- **`StoneRegistry`** (`src/whet/stones/StoneRegistry.hx`) — a named registry of *builders*, not bare
  constructors. A registered type is a `StoneBuilder`: `(key, revivedConfig) -> {stones, routes?,
  mainStone?, update?}`, so one entry can declare a whole multi-stone chain (and skip stages
  conditionally). `register(name, ctor)` is single-stone sugar; `registerBuilder(name, builder)` is the
  general form. Built-ins (`Files`, `JsonStone`, `JsonDb`, `Zip`, `RemoteFile`) self-register on first
  access. When `configSchema()` is a static function on the class, the registry picks it up as the
  type's schema.
- **`StoneStore`** (`src/whet/stones/StoneStore.hx`) — a `StoneFactory` whose entries *are* generic
  JSON stone declarations, backed by a `JsonDb` file (default `stone-store.json`). One JSON file
  describes an entire data-driven stone graph.

## StoneStore entry format

`stone-store.json` is a JSON array of entries. Per entry:

- `id` (required) — stable, explicit; becomes the entry key and the stone id.
- `type` (required) — a `StoneRegistry` type name.
- `config` — the stone config, plain JSON, with reference sentinels revived (see below).
- `mount` — route the entry's `mainStone` into the store's own Router. Either a string
  (`"ui/"` = mount under that dir) or an array of `[routeUnder, filter?, extractDirs?]` routes.
  There is **no `"$self"`** — the entry's mainStone is the implicit target. A `mount` on a type that
  produces no mainStone is an error.
- `disabled: true` — the "commented-out stone" workflow; the entry is skipped entirely at sync.
- `each` + `overrides` — directory-scan expansion (see below).

## `$stone` / `$router` references (config reviver)

Inside `config`, `ConfigReviver` (`src/whet/stones/ConfigReviver.hx`) resolves two sentinels into live
objects:

- `{ "$stone": "<id>" }` → the live stone with that id. Resolution checks sibling store entries first
  (their `mainStone`), then falls back to `project.getStone(id)`, so entries can reference each other
  and script-defined stones regardless of order.
- `{ "$router": <routes> }` → `new Router(<routes>)`, reviving nested `$stone` refs inside the route
  arrays. Plain strings in routes pass through unchanged (a string is already a `Files` shortcut).

A sentinel object must have exactly that one key. Everything else is plain JSON, which is what stone
configs already are.

Because entries reference each other by id, `syncEntries()`:
- **validates all-or-nothing** — structure + per-type `configSchema()` are checked up front; any problem
  aborts sync leaving current stones untouched, with all findings aggregated into one path-specific
  error message.
- **topologically sorts** entries by `$stone` refs (a cycle throws, naming the path).
- **force-updates dependents of any touched entry** (reference-consistency cascade), so an unchanged
  entry never keeps a dead instance of a recreated dependency. The default update is an id-stable
  destroy+recreate (same id + same config → same cache keys, so it's cache-neutral); a builder can
  supply an `update` hook to mutate in place instead.

## `each` expansion

An entry with an `each` clause is a *group*: `each.dir` is scanned for files matching the
`each.pattern` regex, producing one sub-entry per match, keyed `groupId/name` (name via
`each.nameTemplate`). Sparse per-file `overrides` (keyed by derived name) are deep-merged over the base
`config`, and the tokens `$file` / `$name` are substituted throughout `config`, `$router` route arrays,
and `mount`. Scans run **only** during `syncEntries()`, never during `previewEntry` (a perf
invariant). `getExpansion(groupId)` exposes the last scan's files+names for editor tooling.

## Preview semantics

`StoneFactory` keeps a canonical `dataMap` (last-synced data per key). `previewEntry(key, data)`
mutates the *live* stones for a key without recording it as canonical — no regeneration is forced;
whet's hash cache regenerates the affected sub-stones lazily on next `getSource()` because their
configs (and thus hashes) changed. `revertEntry(key)` re-applies the canonical `dataMap` entry (or
removes a preview-created key). A completed `sync()` always reasserts canonical state over any lingering
previews. `StoneStore` extends both with the dependent cascade + route rebuild so previews stay
reference-consistent. This is the mechanism behind live editing of an unsaved config in the editor —
no DB coupling, no baseline snapshot.

## Script rule: reference the store, never its inner stones

A Project file mounts the store as a route source and does nothing else:

```js
const store = await new StoneStore({ id: 'assets-store' }).load('assets/stone-store.json');
bundle.route([['/', store]]); // the store IS a Router
```

Never capture an inner store-created stone instance in script: recreate-on-sync invalidates captured
instances by design. Consume entry outputs through routes (or a `$stone` ref from another entry).

## Hash semantics (StoneFactory extends Router)

Because a factory *is* a `Router`, its `getHash()` is Router's: for the unfiltered case it binds each
route's static structure (mount / filter / extractDirs) to that route's source hash and merges the
per-route tokens order-independently — no id enumeration, so member stones without `list()` aren't
forced to generate. In short, a factory's hash tracks its current route set and each routed stone's
hash; it has no extra self-hash of its own. (`Project.removeStone` deliberately doesn't clear cache, so
stones from removed entries age out via cache durability rules unless you pass the removed keys from
`sync` to `cache.clearStone` — `StoneStore` does this when constructed with `clearCacheOnRemove: true`.)

## CLI: `whet stone-schema [type]`

Prints the registered types (no arg) or a type's `configSchema()` JSON — so an agent can discover
what's editable and legal without reading source.

# Testing

- **Run tests**: `node --test "test/**/*.test.mjs"`
- **Framework**: Node.js built-in test runner (`node:test`) with `node:assert/strict`
- **Test files**: `test/*.test.mjs` — each file covers a specific area (cache, stone, router, etc.)
- **Helpers** (`test/helpers/`):
  - `test-env.mjs`: `createTestProject(name)` creates a temp dir + Project; returns `{ project, rootDir, write, read, exists, cleanup }`
  - `mock-stone.mjs`: `MockStone` extends Stone with configurable `outputs`, `hashKey`, `delayMs`; tracks `generateCount`
- Tests are written in JS (not Haxe) against the compiled `bin/whet.js` output — build before testing
- Haxe private methods (like `generate`, `generateHash`, `list`, `generatePartial`) are overridable from JS subclasses

# Working with Haxe

- **Type system**: Haxe is statically typed; use proper type annotations
- **Abstracts**: Many types like `SourceId`, `StoneId`, `MaybeArray` are abstract types with compile-time transformations
- **Macros**: Build-time code generation used for versioning and post-processing (`whet.Macros`)
- **@:expose metadata**: Makes classes available to JavaScript (see build.hxml for `whet.stones` exposure)
- **JS interop**: Use `js.Syntax.code()` for raw JavaScript when needed
- **Type unification**: `cast` is used for Promise type unification

# Bash Tips

**CRITICAL: Backticks in beans commands** — When updating bean body content that contains backticks (code snippets, template literals, etc.), you MUST use a heredoc with a QUOTED delimiter to prevent bash command substitution:
```bash
# WRONG - backticks will be interpreted by bash
beans update <id> --body-append "text with \`code\`"
echo "text with \`code\`" | beans update <id> --body-append -

# CORRECT - heredoc with quoted delimiter (<<'EOF' not <<EOF)
beans update <id> --body-append "$(cat <<'EOF'
text with `code` and `backticks`
EOF
)"
```
