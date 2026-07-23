---
# whet-qwye
title: 'StoneStore `each` expansion: directory scans with per-file overrides'
status: todo
type: feature
created_at: 2026-07-23T07:07:45Z
updated_at: 2026-07-23T07:07:45Z
parent: whet-1vzf
blocked_by:
    - whet-31lx
---

Generalize AudioDb's group-entry pattern (scan a directory of source files, spawn one sub-entry per match, with sparse per-file config overrides) into StoneStore. This is the capability whose absence would have made AudioDb unmigratable — semantics are kept intentionally identical to AudioDb so a future migration is mechanical.

Reference: `gooye-2/scry/whetstones/assets/AudioDb.mjs` — `scanFiles`, `_expandGroups`, `AudioGroupEntry.overrides`, `deepMerge`.

## Entry format additions

```jsonc
{
  "id": "sfx",
  "type": "AudioChain",                    // any registered type
  "each": {
    "dir": "assets/audio/sfx/",           // scanned recursively, relative to project root
    "pattern": "(.*)\.wav$",             // JS regex on posix path relative to dir
    "nameTemplate": "$1"                   // optional; default '$1'; capture substitution; fallback = file stem
  },
  "config": { "source": "$file", "loudness": { "target": -16 } },
  "overrides": { "punch": { "loudness": { "target": -12 } } },  // keyed by expanded name; sparse deep-merge
  "mount": [["sfx/$name.wav"]]
}
```

## Spec

1. **Promote the scan into core**: `Utils.scanFiles(projectRootAbs:String, dir:String, pattern:String, ?nameTemplate:String):Promise<{files:Array<String>, names:Array<String>}>` in `src/whet/Utils.hx` (or a small new module if Utils doesn't fit) — port `AudioDb.scanFiles` near-verbatim: recursive readdir, skip dot-dirs and node_modules, posix separators, files returned project-root-relative, `$n` capture substitution with file-stem fallback, results sorted by file path. AudioDb's own migration to this helper happens later in the scry repo — do not touch scry here.
2. **Replace StoneStore.expandEntries** (identity hook from whet-31lx): entries without `each` pass through 1:1. With `each`, for each match i:
   - `key = entry.id + '/' + names[i]`
   - `raw = deepMerge(entry.config, entry.overrides?.[names[i]])` — reuse `ConfigStore.deepMerge` (already a public static; arrays/primitives replace wholesale, objects merge). Overrides may themselves contain tokens.
   - `config = substituteTokens(raw)`: recursively, in every string value (including inside `$router` route arrays), replace `$file` → files[i] and `$name` → names[i] (plain substring replacement; document that literal `$file`/`$name` text is unsupported — no escape mechanism).
   - `mount = substituteTokens(entry.mount)` — enables per-file mounts as above.
3. Expanded keys participate in topo sort / cascade / preview like any key; refs TO a sub-entry use the full `groupId/name` key. `overrides` keys that match no expanded name → validation warning (typo guard).
4. **Collisions**: duplicate expanded name within a group, or expanded key colliding with another entry's key → aggregated sync validation error listing the offending files.
5. **Introspection for the future editor plugin**: `getExpansion(entryId:String):Null<{files:Array<String>, names:Array<String>}>` (`@:keep`), cached per syncEntries run (mirror of AudioDb.groupMatches).
6. **Perf invariant** (the scry-app-y4be friction-1 fix, keep it): scans run only inside `syncEntries()`; `previewEntry` (StoneFactory) never triggers a rescan — previews of expanded sub-entries send the merged single-file config keyed by the expanded key, same convention scry-app-y4be uses.
7. Validation additions: `each.dir` non-empty string, `each.pattern` compiles as RegExp (wrap in try/catch → aggregated error), `overrides` only allowed together with `each`.

## Todos

- [ ] Utils.scanFiles port + unit tests (nested dirs, dot-dir/node_modules skip, capture templates, stem fallback, sort order)
- [ ] expandEntries implementation + token substitution + collision/typo validation + getExpansion
- [ ] Tests in `test/stone-store.test.mjs` (extend): temp tree of files → expected keys/configs; override deep-merge (nested object merge, array replace); tokens substituted inside $router and mount; re-sync after adding a file picks it up, after deleting removes the sub-entry (and its dataMap key); collision error; overrides-typo warning; previewEntry on an expanded key works without rescan (assert scanFiles call count via a spy or counter)
- [ ] Rebuild + full test run green
