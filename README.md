# Whet

A NodeJS-based tool for managing things every project needs, such as configuration, build scripts, assets, etc., using a flexible everything-is-an-asset approach, with configurable caching.

## Project Files

Project files define a project, its [stones](#Stones). Their content defines what [commands](#Commands) are available.

## Stones

Stones (named after _whetstone_) are individual building blocks of a project.

They represent a single logical asset (can be multiple files) or functionality (e.g. a dev web server). Stones can use other stones (via routes), to achieve their objective, forming a dependency tree. E.g. a CSS file could be made by minifying a file generated from SCSS source, and each step could be individually cached.

### Stones Configuration

Stones try to keep all their state in a `config` object. Each stone requires it to be supplied. The `config` object should be designed for scripting, i.e. allow dynamic types as long as they make sense.

Reading and applying the configuration should be limited to generating resources/hashes from the stone. Invalid configuration therefore won't crash the project initialization until it's being used. This is just a guideline and not a requirement, and stones might validate the configuration immediately where it makes sense.

<!-- TODO: Implement, and then mention `project.getHash()` as a way to verify the whole project. -->

Some stones might provide helper methods to modify the configuration after it was passed in. Such methods might modify the `config` object, e.g. turning a single entry into array of them.

### Hashes

...

### Commands

...

## Routers

...

## Data-Driven Stones

Normally a project file wires stones by hand. When a *data* file should instead decide **which** stones
exist and how they connect, whet has a data-driven layer:

- **StoneFactory** — the base lifecycle for a set of stones driven by external data. It extends
  `Router`, so a factory is itself a route source. `sync(data, keyFn)` creates/updates/removes entries
  to match the data (returning removed keys for cache cleanup), and it supports live **preview/revert**
  of an unsaved config against a retained canonical baseline.
- **StoneRegistry** — a named registry mapping a type name (`"Files"`, `"Zip"`, a project's own
  stone…) to a *builder* that produces one or more stones. Built-ins self-register; project and library
  stones register at import time.
- **StoneStore** — a `StoneFactory` whose entries are generic JSON declarations, backed by a JSON file
  (default `stone-store.json`). One file can describe an entire stone graph, so adding an asset folder
  or toggling a stage becomes a data edit rather than a code change.

An entry is `{ id, type, config, mount?, disabled?, each? }`. Inside `config`, the sentinels
`{ "$stone": "id" }` and `{ "$router": [...] }` are revived into the live stone / a `Router` — this is
how one entry references another, so entries are synced in dependency (topological) order and validated
all-or-nothing before anything is touched. An `each` clause expands a directory scan into one sub-entry
per matching file (with per-file `overrides` and `$file`/`$name` tokens).

A script mounts the store and nothing more — it references the store (or entry outputs via routes),
never the inner stones, which are recreated on sync by design:

```js
const store = await new StoneStore({ id: 'assets-store' }).load('assets/stone-store.json');
bundle.route([['/', store]]); // the store IS a Router
```

`whet stone-schema [type]` prints the registered types, or one type's config schema.

See `CLAUDE.md` for the full entry format and semantics, and
`docs/ecosystem-review-2026-07/03-data-driven-stones.md` for the design rationale.

## Core Concepts

Project files should have no side effects, unless some of their commands are executed. They only process the active configuration, initializing the available commands.

<!-- TODO: document configuration handlers -->

All file paths should use `/` as directory separator, regardless of platform.

Paths should always be relative, and are considered relative to root project directory, or relative to root of the Router/Stone used. For getting sources from Stones/Routers [minimatch](https://github.com/isaacs/minimatch/) is used.

Path that is a directory ends with a `/`, otherwise it's considered a file. That means:

- `assets/` is a **directory** called `assets`.
- `assets` is a **file** called `assets`.
