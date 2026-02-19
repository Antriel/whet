---
# whet-wb1n
title: Stone ID with colons breaks file path construction
status: completed
type: bug
priority: normal
created_at: 2026-02-19T12:07:04Z
updated_at: 2026-02-19T12:11:46Z
---

In Stone.hx, duplicate stone IDs are created with colon separators (e.g., 'MyStone:2'). However, CacheManager.hx:64 uses stone.id directly in path construction: `var baseDir:SourceId = stone.id + '/';`

This causes problems:
- On Windows, colons have special meaning in paths and can cause path resolution issues
- On Unix, colons in directory names are allowed but unusual and may break tools expecting standard path names
- The ':' character should be sanitized or replaced with an appropriate path-safe character

**Location**: CacheManager.hx:64, called from getDir() method

**Related**: Stone.hx:52 (duplicate ID deduplication)

## Summary of Changes

Fixed in `CacheManager.getDir()` (line 64): added a sanitization step that replaces any character not in `[a-zA-Z0-9_\-.]` with `_` before using the stone ID as a directory name component.

```haxe
var safeId = ~/[^a-zA-Z0-9_\-.]/g.replace(stone.id, '_');
var baseDir:SourceId = safeId + '/';
```

Added two tests in `test/stone.test.mjs`:
- `Stone with colon in ID can use file cache without path issues` — covers the auto-dedup case (`MyStone:2`)
- `Stone with arbitrary special chars in ID can use file cache` — covers user-provided IDs with `/`, `?`, `=`, `&`
