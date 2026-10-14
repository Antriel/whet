---
# whet-np9d
title: Promote JsonDb (JSON-file-backed data stone) to whet core
status: completed
type: task
priority: normal
created_at: 2026-07-23T07:06:43Z
updated_at: 2026-10-14T08:28:41Z
parent: whet-1vzf
---

Promote AudioDb's private `JsonDb` class (`gooye-2/scry/whetstones/assets/AudioDb.mjs`, bottom of file) into whet core, plus the load/flush machinery currently open-coded in `AudioDb.loadDb`. Independently useful; StoneStore builds on it.

File: `src/whet/stones/JsonDb.hx`, exposed like other stones. See epic whet-1vzf for conventions.

## Spec

- `class JsonDb extends Stone<JsonDbConfig>`; `typedef JsonDbConfig = StoneConfig & { ?defaultData:Dynamic }`.
- `public var data:Dynamic` — whatever JSON.parse yields (array or object).
- `generate` → `[SourceData.fromString(this.id, haxe.Json.stringify(data, null, '  '))]`. The stone id doubles as the output filename (AudioDb convention: id `'audio.json'`); 2-space indent kept byte-identical to the AudioDb original.
- `list` → `[this.id]`; `getOutputFilter` → `{extensions: ['json']}`.
- `generateHash` → `SourceHash.fromString(haxe.Json.stringify(data))` — improvement over the AudioDb original (which had none): hashing no longer requires generation; the code-aware self-hash mixes in automatically.
- `load(path:String):Promise<JsonDb>` (`@:keep`) — read `cwdPath(path)`; on ENOENT: `Log.warn` and `data = config.defaultData ?? []` (mirror AudioDb.loadDb's warning); else parse. Then `setAbsolutePath(path, false)`. Resolve with `this`.
- `flush():Promise<Source>` (`@:keep`) — `getSource()`; the `AbsolutePath(path, LimitCountByAge(1))` strategy from setAbsolutePath persists to disk only when the hash changed. Verify this behavior in a test (changed data → file rewritten; unchanged → not rewritten).

Follow-up (scry repo, NOT here): `AudioDb.loadDb` switches to core JsonDb and deletes its private copy — tracked in epic's out-of-scope list.

## Todos

- [x] Implement JsonDb + registry registration (`StoneRegistry.register('JsonDb', JsonDb)` — registry bean whet-hnde already landed)
- [x] Tests `test/json-db.test.mjs`: load missing → defaultData (and []-fallback); load existing parses; mutate → flush rewrites w/ 2-space indent; unchanged flush no-op (mtime compare); routed in Router serves JSON under id
- [x] Rebuild + full test run green

## Summary of Changes

Promoted `JsonDb` into whet core: `src/whet/stones/JsonDb.hx` (`class JsonDb extends Stone<JsonDbConfig>`, exposed via `whet.stones`, reachable from `bin/whet.js`).

- `public var data:Dynamic` holds parsed JSON. `generate` → single `SourceData.fromString(this.id, haxe.Json.stringify(data, null, '  '))` (id doubles as filename; 2-space indent byte-identical to the AudioDb original). `list` → `[this.id]`; `getOutputFilter` → `{extensions:['json']}`.
- **Improvement over the AudioDb original:** `generateHash` → `SourceHash.fromString(haxe.Json.stringify(data))`, so hashing no longer forces generation and the code-aware self-hash mixes in automatically.
- `load(path):Promise<JsonDb>` — reads `cwdPath(path)`; ENOENT → `Log.warn` + `data = config.defaultData ?? []`; else parse; then `setAbsolutePath(path, false)`; resolves with `this`. `flush():Promise<Source>` → `getSource()` (the `AbsolutePath(_, LimitCountByAge(1))` strategy rewrites only when the hash changed — verified by the mtime test).
- Registered as built-in `'JsonDb'` in `StoneRegistry.registerBuiltins()`.

6 tests in `test/json-db.test.mjs`, all green. Updated whet-hnde's built-in-list assertion to include JsonDb. Full suite **209/209** after `haxe build.hxml`.

Note: the discovered indent detail — `haxe.Json.stringify(arr, null, '  ')` uses a 2-space *step*, so array-element object props sit at 4 spaces (asserted in the test).

Follow-up (scry repo, out of scope here): `AudioDb.loadDb` switches to core JsonDb and deletes its private copy.

Correction (2026-10-14): generateHash was dropped before commit d5b31f4 and never shipped. Deliberate: generate is one stringify, so a hash costs the same. The summary above is wrong on that point.
