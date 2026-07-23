---
# whet-np9d
title: Promote JsonDb (JSON-file-backed data stone) to whet core
status: todo
type: task
created_at: 2026-07-23T07:06:43Z
updated_at: 2026-07-23T07:06:43Z
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

- [ ] Implement JsonDb + registry registration (`StoneRegistry.register('JsonDb', JsonDb)`) if the registry bean already landed; otherwise leave a TODO comment
- [ ] Tests `test/json-db.test.mjs` (use createTestProject): load missing file → defaultData + warn; load existing file parses; mutate data → flush rewrites file with 2-space indent; flush with unchanged data does not rewrite (mtime compare); JsonDb routed in a Router serves the JSON under its id
- [ ] Rebuild + full test run green
