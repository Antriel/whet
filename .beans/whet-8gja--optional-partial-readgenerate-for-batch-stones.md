---
# whet-8gja
title: Optional partial read/generate for batch Stones
status: todo
type: feature
priority: normal
created_at: 2026-02-17T08:34:27Z
updated_at: 2026-02-17T09:35:50Z
parent: whet-juli
blocked_by:
    - whet-flfg
---

Add optional per-Stone capability for partial generation, integrated natively into the existing cache infrastructure. Partial and full generation share the same cache pool — files generated partially are reusable by full generation and vice versa.

## Goal

Enable stones that produce many outputs (e.g., SharpStone processing 100+ images) to generate a single requested output efficiently, while caching it in the same pool that full generation uses. This enables fast live preview (process 1 image instead of 100+) and avoids redundant work when full generation later runs.

## Key Constraint: generateHash() Is Required for Partial Caching

Current cache behavior for stones WITHOUT `generateHash()`: the hash is computed from the byte content of ALL generated outputs. This means:
- Full generation hash = hash(all output bytes merged)
- Partial generation would produce a different hash (fewer bytes)
- They can never share cache entries because their hashes differ

**Therefore: stones that want to benefit from partial generation MUST implement `generateHash()`.** This is already recommended as an optimization (Files stone does it). For stones without `generateHash()`, partial requests fall back to full generation + filter — the existing behavior, just formalized.

This is a reasonable soft requirement, not a breaking change. Document it clearly.

## Cache Entry Model: Growable Entries

Currently, one cache entry = one complete Source (hash + all files). The proposal: cache entries can be **partial** (a subset of outputs) and **grow** as more outputs are requested.

### Entry structure change

Current `RuntimeFileCacheValue`:
```
{ hash, ctime, baseDir, files: [{ id, fileHash, filePath, mtime, size }] }
```

Add a `complete` flag:
```
{ hash, ctime, baseDir, complete: Bool, files: [{ id, fileHash, filePath, mtime, size }] }
```

- `complete = true`: all stone outputs are present (equivalent to current behavior)
- `complete = false`: only some outputs are present

For MemoryCache, the Value is `Source`. Add `complete` field to `Source` directly (Source is already cache-aware with `origin`, `ctime`, `getDirPath`).

### Cache lookup behavior

**Partial request** (`getPartialSource(sourceId)`):
1. Find entry by hash
2. If entry exists and contains the requested sourceId -> return it (cache hit)
3. If entry exists but doesn't contain sourceId, and `complete = true` -> sourceId doesn't exist in this stone
4. If entry exists but doesn't contain sourceId, and `complete = false` -> generate just this output, add to entry
5. If no entry -> generate just this output, create new partial entry

**Full request** (`getSource()`, existing path):
1. Find entry by hash
2. If entry exists and `complete = true` -> return all (existing behavior, no change)
3. If entry exists and `complete = false` -> partial entry found, need to complete it (see "Completing a partial entry" below)
4. If no entry -> generate everything, store as complete (existing behavior, no change)

### Completing a partial entry (full generation finds partial cache)

**Decision: Option B — generate only missing outputs, merge into entry.** Gracefully degrades when `list()` is not overridden.

**With `list()` overridden** (stone knows its full output set without generating):
- Get full set of output IDs via `list()` (the private method, called directly by cache via `@:allow`)
- Diff against what's already in the partial entry
- Call `generatePartial()` for each missing sourceId
- Merge results into the entry, mark `complete = true`
- Maximum reuse, no redundant computation

**Without `list()` overridden** (default returns `null` — stone can't enumerate without generating):
- `list()` returns null, so we can't determine what's missing
- Fall back: call `generateSource(hash)` to get everything, replace the partial entry with complete result
- This is effectively Option A behavior, but it's the natural fallback, not a separate code path

**Why previous concerns are non-issues:**
- "What if `list()` output changes between sessions?" — Stone hash would change, so partial entry wouldn't be found. Non-issue.
- "Items generated at different times, is combined hash still valid?" — This path only works when `generateHash()` is implemented (input-based hash). If it's not, partial entries can't exist in the first place. Non-issue.

## Stone API Changes

### Refactor: `list()` / `listIds()` split

Currently `list()` is public with a default that calls `getSource()`. Refactor to match the `generateHash()`/`getHash()` pattern:

**Current:**
```haxe
public function list():Promise<Array<SourceId>> {
    return getSource().then(source -> source.data.map(sd -> sd.id));
}
```

**New — private `list()` with null default:**
```haxe
/**
 * Optional override: return the list of output sourceIds this stone produces,
 * without triggering generation. Return null if unknown (default).
 * Used by cache for partial entry completion and by listIds() as fast path.
 */
private function list():Promise<Null<Array<SourceId>>> {
    return Promise.resolve(null);
}
```

**New — public `listIds()` with fallback:**
```haxe
/**
 * Public API for getting output IDs. Calls list(), falls back to
 * full generation if list() returns null.
 */
public final function listIds():Promise<Array<SourceId>> {
    return list().then(ids -> {
        if (ids != null) return ids;
        return getSource().then(source -> source.data.map(sd -> sd.id));
    });
}
```

**Impact on existing code:**
- 6 stones override `list()` (Files, JsonStone, Zip, RemoteFile, Hxml, HaxeBuild) — they keep working, their overrides now return non-null lists as before, just the method is now private
- 3 call sites switch from `list()` to `listIds()`: `Router.hx:60`, `Project.hx:69`, `HaxeBuild.hx:58` (`super.list()` → `super.listIds()`)
- Cache completion calls `list()` directly via `@:allow` — gets null if stone can't enumerate cheaply, gets the list if it can

### New optional override: `generatePartial`

```haxe
/**
 * Optional override for partial generation.
 * Called when a single output is requested via getPartialSource().
 * Return data for the requested sourceId, or null to signal
 * "not supported" (triggers fallback to full generation + filter).
 */
private function generatePartial(sourceId:SourceId, hash:SourceHash):Promise<Null<Array<SourceData>>> {
    return Promise.resolve(null); // Default: not supported
}
```

### New public final: `getPartialSource`

The `generateHash()` check is the **gating mechanism** — it happens here, before entering the cache:

```haxe
/**
 * Get source for a single output by sourceId.
 * If the stone implements generatePartial(), generates just the requested output.
 * Otherwise falls back to full generation + filter.
 * Uses the same cache as getSource() — partial and full share the pool.
 */
public final function getPartialSource(sourceId:SourceId):Promise<Source> {
    // Gate: check if we have an input-based hash. If not, partial caching
    // is impossible (hash depends on output bytes), so fall back to full gen + filter.
    return finalMaybeHash().then(hash -> {
        if (hash == null)
            return getSource().then(source -> source.filterTo(sourceId));
        else
            return cache.getPartialSource(this, sourceId);
    });
}
```

**Important**: `finalMaybeHash()` is the right method to use here — it calls `generateHash()` and finalizes with dependency hashes, returning `null` when `generateHash()` isn't overridden.

### New internal: `generatePartialSource`

Called by cache on miss. **Must not re-enter the cache** (to avoid loops).

```haxe
/**
 * Called by cache infrastructure. Generates partial source directly,
 * never goes back through cache methods.
 */
@:allow(whet.cache) final function generatePartialSource(sourceId:SourceId, hash:SourceHash):Promise<{source:Source, complete:Bool}> {
    if (!this.locked) throw new js.lib.Error("Acquire a lock before generating.");
    // Initialize dependencies (same as generateSource).
    var init = if (config.dependencies != null) Promise.all([
        for (stone in makeArray(config.dependencies)) stone.getSource()
    ]) else Promise.resolve(null);
    return init.then(_ -> {
        return generatePartial(sourceId, hash).then(data -> {
            if (data != null) {
                // Stone supports partial generation — wrap as incomplete Source.
                return { source: new Source(data, hash, this, Sys.time(), false), complete: false };
            } else {
                // Not supported — full generation, then filter.
                // Call generate() directly, NOT getSource(), to avoid re-entering cache.
                return generate(hash).then(allData -> {
                    var fullSource = new Source(allData, hash, this, Sys.time(), true);
                    return { source: fullSource, complete: true };
                });
            }
        });
    });
}
```

The cache layer uses the `complete` flag from the return value to decide how to store the result. When `complete = true`, the full source is cached, and the caller filters to the requested `sourceId` from the returned full source.

### Loop prevention

The critical invariant: **`generatePartialSource` and `generateSource` call `generate()`/`generatePartial()` directly, never `getSource()`/`getPartialSource()`**. The cache layer calls these `generate*Source` methods. This keeps the cache as the single entry point, with everything below it being direct calls. No re-entrant cache access = no loops.

Similarly, the completion path in `BaseCache.get()` (when finding a partial entry) must call `list()` (private, via `@:allow`) and `generatePartialSource`/`generateSource` directly, not `listIds()`/`getPartialSource`/`getSource`.

### Completing a partial entry — detailed flow in BaseCache.get()

When `BaseCache.get()` finds a partial entry (`complete = false`):

**Completion flow:**
1. Call `stone.list()` (private, via `@:allow`) — returns null or list of all output IDs
2. If returns list: diff against partial entry files, call `stone.generatePartialSource(missingId, hash)` for each missing one, merge into entry, mark complete
3. If returns null: call `stone.generateSource(hash)` to get everything, replace partial entry with complete one

## Cache Interface Changes

### `Cache.hx` — add to interface

```haxe
public function getPartial(stone:AnyStone, sourceId:SourceId, durability:CacheDurability, check:DurabilityCheck):Promise<Source>;
```

### `BaseCache.hx` — add `getPartial` method

Similar to `get()` but:
- Uses the SAME hash (partial and full share the hash because both use `generateHash()`).
- The hash is already known (non-null) — we only reach this path when `finalMaybeHash()` returned a value (gated in `Stone.getPartialSource`).
- On cache hit: checks if the entry contains the requested sourceId. If yes, returns filtered Source. If entry is complete but sourceId not found, returns null/error.
- On cache miss (entry doesn't have sourceId and `complete = false`): calls `generatePartialSource(sourceId, hash)`, then **adds the result to the existing entry** (mutable entry — append to file list, update cache).
- On no entry at all: calls `generatePartialSource(sourceId, hash)`, creates new entry.

### `BaseCache.hx` — modify `get` method (full generation path)

- After finding an entry by hash, check the `complete` flag.
- If `complete = false`: call `stone.list()` (private, via `@:allow`). If non-null, complete incrementally via `generatePartial` for missing items. If null, fall back to full `generateSource` replacing the entry.
- If `complete = true`: existing behavior (validate and return).

### `FileCache.hx` — changes

- Add `complete` field to `RuntimeFileCacheValue` and `FileCacheValue`.
- Serialize/deserialize in cache.json.
- **Existing entries without `complete` field**: treat as `complete = true` (backward compatible — all existing entries are full generations).
- `value()` function: accept `complete` parameter. Set `complete = true` when storing from `generateSource` (full), `complete = false` from `generatePartialSource`.
- Partial file storage: same baseDir as full would use (same hash -> same `getUniqueDir`). Files accumulate in the directory.

### `MemoryCache.hx` — changes

- Value type is `Source`. The `complete` flag lives on Source itself.
- No wrapper needed.

### `CacheManager.hx` — add routing method

```haxe
public function getPartialSource(stone:AnyStone, sourceId:SourceId):Promise<Source> {
    return switch stone.cacheStrategy {
        case None:
            stone.acquire(() -> stone.finalMaybeHash().then(hash ->
                stone.generatePartialSource(sourceId, hash).then(r -> r.source.filterTo(sourceId))));
        case InMemory(durability, check):
            memCache.getPartial(stone, sourceId, durability, check ?? AllOnUse);
        case InFile(durability, check) | AbsolutePath(_, durability, check):
            fileCache.getPartial(stone, sourceId, durability, check ?? AllOnUse);
    };
}
```

Note: for `None` strategy, `finalMaybeHash()` is guaranteed non-null here (gated in `Stone.getPartialSource`).

## Source Changes

Add `complete` field to `Source`:

```haxe
class Source {
    public final data:Array<SourceData>;
    public final hash:SourceHash;
    public final origin:AnyStone;
    public final ctime:Float;
    public final complete:Bool; // New field, defaults to true

    @:allow(whet.Stone)
    @:allow(whet.cache)
    private function new(data, hash, origin, ctime, complete = true) {
        // ... existing code ...
        this.complete = complete;
    }

    /** Filter to a single sourceId. Returns a Source containing only that entry (or empty). */
    public function filterTo(sourceId:SourceId):Source {
        var filtered = data.filter(d -> d.id == sourceId);
        return new Source(filtered, hash, origin, ctime, complete);
    }
}
```

## Project API Change

Update `getStoneSource` to use partial path when sourceId is provided:

```haxe
public function getStoneSource(id:String, ?sourceId:SourceId):Promise<Null<Source>> {
    final stone = getStone(id);
    return if (stone == null) Promise.resolve(null)
    else if (sourceId != null) stone.getPartialSource(sourceId)
    else stone.getSource();
}
```

## Interaction Matrix

| Stone capabilities | Partial request | Full request finding partial entry |
|---|---|---|
| No `generateHash` | Full gen + filter via `getSource()`. No partial caching (gated out in `getPartialSource`). | N/A — partial entries cannot exist. |
| `generateHash` only, no `generatePartial` | `generatePartialSource` returns null from `generatePartial` -> falls back to full `generate()`, cached as **complete**. Subsequent partial requests served from cache. | N/A — entries are always complete (fallback always does full gen). |
| `generateHash` + `generatePartial`, no `list()` override | Single output generated, cached as partial entry. | `list()` returns null -> full `generateSource()`, replaces partial with complete. |
| `generateHash` + `generatePartial` + `list()` override | Single output generated, cached as partial entry. | Diff + `generatePartial()` for each missing -> merge, mark complete. Maximum reuse. |

## Resolved Design Decisions

### Q1: Mutable entries
Entries are mutable. After generating a partial output, mutate the existing entry's file list and update the cache. FileCache already mutates for use-ordering.

### Q2: Cache directory sharing
Partial and full share the same directory. `getUniqueDir` returns the same dir for the same hash.

### Q3: None cache strategy
No caching. Partial generates and returns without storing. Fine.

### Q4: Durability rules
Same rules for partial and full entries. No special treatment.

### Q5: Concurrency
Handled by existing `acquire()` lock.

### Q6: list() refactor
Refactor `list()` to match the `generateHash()`/`getHash()` pattern: private `list()` returns null by default (overridden by stones that can enumerate without generating), new public `listIds()` handles the fallback to full generation. Cache calls `list()` directly via `@:allow`. No new method needed — just a visibility change + public wrapper. 6 existing overrides (Files, JsonStone, Zip, RemoteFile, Hxml, HaxeBuild) keep working. 3 call sites (Router, Project, HaxeBuild super call) switch to `listIds()`.

## Files to Modify

1. `src/whet/Stone.hx` — refactor `list()` to private + add `listIds()` public, add `generatePartial`, `getPartialSource`, `generatePartialSource`
2. `src/whet/Source.hx` — add `complete` field, add `filterTo` method
3. `src/whet/cache/Cache.hx` — add `getPartial` to interface
4. `src/whet/cache/BaseCache.hx` — add `getPartial`, modify `get` for complete flag + completion logic
5. `src/whet/cache/FileCache.hx` — add `complete` to value type, serialization
6. `src/whet/cache/MemoryCache.hx` — handle partial Source values (via Source.complete)
7. `src/whet/cache/CacheManager.hx` — add `getPartialSource` routing
8. `src/whet/Project.hx` — update `getStoneSource`, switch `list()` → `listIds()`
9. `src/whet/route/Router.hx` — switch `list()` → `listIds()`
10. `src/whet/stones/haxe/HaxeBuild.hx` — switch `super.list()` → `super.listIds()`

## Implementation Plan

### Step 1: Source.complete and Source.filterTo
- Add `complete:Bool` field to `Source` constructor (default `true`)
- Add `filterTo(sourceId)` method
- All existing callers unaffected (default = true)

### Step 2: Refactor list() + Stone API additions
- Refactor `list()`: make private, change default to return null (instead of `getSource().then(...)`)
- Add `listIds()` — public final, calls `list()`, falls back to `getSource().then(...)` if null
- Update 6 existing `list()` overrides — no code changes needed (just visibility, Haxe handles this)
- Update 3 call sites: `Router.hx`, `Project.hx`, `HaxeBuild.hx` → switch to `listIds()`
- Add `generatePartial(sourceId, hash)` — private, default returns null
- Add `getPartialSource(sourceId)` — public final, with `finalMaybeHash()` gate
- Add `generatePartialSource(sourceId, hash)` — `@:allow(whet.cache)` final

### Step 3: Cache interface
- Add `getPartial` to `Cache.hx` interface

### Step 4: FileCache value type
- Add `complete` field to `RuntimeFileCacheValue` and `FileCacheValue`
- Backward compat: missing field = `true`
- Update serialization/deserialization

### Step 5: BaseCache.getPartial
- Implement partial cache lookup and generation
- Handle: cache hit (has sourceId), cache hit (complete, no sourceId = doesn't exist), cache miss (incomplete, generate + add), no entry (generate + create)

### Step 6: BaseCache.get modification
- Check `complete` flag on found entries
- If incomplete: attempt completion via `list()` + per-item `generatePartial`, or fall back to full `generateSource` replacing entry

### Step 7: MemoryCache updates
- Source already carries `complete` — MemoryCache uses Source as value, so it works naturally
- May need minor adjustments for the `getPartial` implementation

### Step 8: CacheManager.getPartialSource
- Route to appropriate cache based on `cacheStrategy`

### Step 9: Project.getStoneSource
- Add optional `sourceId` parameter, route to `getPartialSource` when provided

### Step 10: Tests
- Partial generation returns correct single output (fallback path — no `generatePartial`)
- Partial generation with `generatePartial` override
- Cache sharing: partial then full, full then partial
- Cache completion: with `list()` (incremental), without (full replace)
- Cache isolation: different sourceIds cached correctly within same entry
- Gate check: stone without `generateHash` falls back to full gen + filter

## TODO

- [x] Design: resolve open questions
- [ ] Step 1: Add Source.complete field and Source.filterTo method
- [ ] Step 2: Refactor list()/listIds() + add generatePartial, getPartialSource, generatePartialSource
- [ ] Step 3: Add Cache.getPartial interface method
- [ ] Step 4: Update FileCache value type and serialization for complete flag
- [ ] Step 5: Implement BaseCache.getPartial with growable entry support
- [ ] Step 6: Modify BaseCache.get to handle complete flag + completion logic
- [ ] Step 7: Update MemoryCache for partial Source handling
- [ ] Step 8: Add CacheManager.getPartialSource routing
- [ ] Step 9: Update Project.getStoneSource to use partial path
- [ ] Step 10: Tests
