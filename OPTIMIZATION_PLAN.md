# Whet Router Performance Optimization Plan

## Problem Summary

When routing requests through a complex Stone dependency tree, hash computation cascades through all dependencies. A single `get()` call on the bundle router takes ~200ms, with 70% spent on hash computation (1500 hashes across 270MB of source files).

The cascade happens because:
1. `Router.get(pattern)` calls `list()` on each source Stone
2. `Stone.list()` defaults to `getSource()` which validates cache via hash
3. Hash validation calls `generateHash()` which hashes all config Routers
4. `Router.getHash()` calls `get()` on its sources, recursing into more Stones

Even with file-based caching, every request recomputes hashes to validate cache entries.

---

## Optimization 1: Mtime-Based Hash Cache

### Goal
Avoid re-reading and re-hashing file contents when files haven't changed. Use file modification time (mtime) and size as a proxy for content changes.

### Design

**New class: `HashCache`**

Stores mappings of `(filePath, mtime, size) → hash` in memory and persists to disk.

```
.whet/hash-cache.json
{
  "assets/img/title.png": {
    "mtime": 1704672000000,
    "size": 45032,
    "hash": "a1b2c3..."
  },
  ...
}
```

### Implementation Steps

#### Step 1: Create HashCache class

Location: `src/whet/cache/HashCache.hx`

```haxe
class HashCache {
    static var instance:HashCache;

    var cache:Map<String, CachedHash>;  // path → {mtime, size, hash}
    var dirty:Bool = false;

    public static function get():HashCache {
        if (instance == null) instance = new HashCache();
        return instance;
    }

    /**
     * Get hash for file, using cache if mtime/size match.
     * Returns cached hash or computes new one.
     */
    public function getFileHash(path:String):Promise<SourceHash> {
        return new Promise((res, rej) -> {
            Fs.stat(path, (err, stats) -> {
                if (err != null) { rej(err); return; }

                var cached = cache.get(path);
                if (cached != null &&
                    cached.mtime == stats.mtimeMs &&
                    cached.size == stats.size) {
                    res(SourceHash.fromHex(cached.hash));
                    return;
                }

                // Cache miss - read and hash
                Fs.readFile(path, (err, data) -> {
                    if (err != null) { rej(err); return; }
                    var hash = SourceHash.fromBytes(data);
                    cache.set(path, {
                        mtime: stats.mtimeMs,
                        size: stats.size,
                        hash: hash.toHex()
                    });
                    dirty = true;
                    res(hash);
                });
            });
        });
    }

    public function flush():Promise<Nothing> { ... }
}
```

#### Step 2: Modify SourceHash.fromFile()

Location: `src/whet/SourceHash.hx`

Change `fromFile` to use the cache:

```haxe
public static function fromFile(path:String):Promise<SourceHash> {
    return HashCache.get().getFileHash(path);
}
```

#### Step 3: Batch stat operations

For `SourceHash.fromFiles()`, collect all paths first, then do parallel stat calls:

```haxe
public static function fromFiles(paths, filter, recursive):Promise<SourceHash> {
    // Collect all file paths first
    return collectAllPaths(paths, filter, recursive)
        .then(allPaths -> {
            // Parallel hash lookups (each uses mtime cache internally)
            return Promise.all(allPaths.map(p -> HashCache.get().getFileHash(p)));
        })
        .then(hashes -> merge(...hashes));
}
```

#### Step 4: Persist cache on process exit

In `Whet.hx` or `Project.hx`, add shutdown hook:

```haxe
js.Node.process.on('beforeExit', _ -> HashCache.get().flush());
```

### Expected Impact

- First run: Same as before (read all files, compute hashes)
- Subsequent runs: ~0.1ms per file (stat) instead of ~1ms (read+hash)
- For 1500 files: ~150ms stat time vs ~1500ms read+hash time
- Overall: 200ms → ~60-80ms (estimated 60-70% reduction)

### Correctness Guarantee

Mtime-based caching is deterministically correct:
- If file content changes, OS updates mtime
- If mtime unchanged, content is unchanged
- This is the same guarantee used by `make`, `ninja`, and other build tools

---

## Optimization 2: Output Pattern Filtering

### Goal
Skip entire Stone subtrees when their output patterns can't possibly match the query. When looking for `audio/n_1.ogg`, don't enumerate image-producing Stones at all.

### Design

**Two-stage filtering:**

1. **Quick check (O(1))**: Extension-based lookup
   - Stone declares: `outputExtensions: ['png', 'webp']`
   - Query has extension `.ogg` → no match → skip Stone entirely

2. **Precise check (O(pattern count))**: Glob pattern matching
   - Stone declares: `outputPatterns: ['multiatlas_*.png', 'multiatlas.json']`
   - Query `title.png` doesn't match any pattern → skip Stone

Stage 2 only runs if Stage 1 passes (extensions overlap).

### Data Structures

```typescript
interface OutputFilter {
    // Stage 1: Quick extension check (null = any extension)
    extensions?: Set<string>;  // e.g., {'png', 'json'}

    // Stage 2: Glob patterns (null = matches anything with valid extension)
    patterns?: string[];  // e.g., ['multiatlas_*.png', 'multiatlas.json']
}
```

### Implementation Steps

#### Step 1: Add outputFilter to Stone base class

Location: `src/whet/Stone.hx`

```haxe
abstract class Stone<T:StoneConfig> {
    /**
     * Optional filter describing what this Stone can produce.
     * Used by Router to skip Stones that can't match a query.
     * If null, Stone is assumed to potentially produce anything.
     */
    public var outputFilter:Null<OutputFilter> = null;

    // ... existing code
}

typedef OutputFilter = {
    /** File extensions this Stone can produce (without dot). Null = any. */
    var ?extensions:Array<String>;

    /** Glob patterns for output files. Null = matches any file with valid extension. */
    var ?patterns:Array<String>;
}
```

#### Step 2: Create OutputFilterMatcher utility

Location: `src/whet/route/OutputFilterMatcher.hx`

```haxe
class OutputFilterMatcher {

    /**
     * Check if a query could possibly match a Stone's output filter.
     * Returns true if the Stone should be enumerated, false if it can be skipped.
     *
     * @param query The search pattern (often a specific file path)
     * @param filter The Stone's output filter (null = matches anything)
     * @param queryIsPattern True if query contains wildcards
     */
    public static function couldMatch(query:String, filter:Null<OutputFilter>,
            queryIsPattern:Bool):Bool {
        if (filter == null) return true;  // No filter = could produce anything

        // Stage 1: Extension check
        if (filter.extensions != null) {
            var queryExt = getExtension(query);
            if (queryExt != null && !filter.extensions.contains(queryExt)) {
                return false;  // Extension mismatch - definitely skip
            }
            // If query has no extension (pattern like 'assets/**'), can't filter by ext
        }

        // Stage 2: Pattern check (only for specific file queries)
        if (!queryIsPattern && filter.patterns != null) {
            // Query is a specific file - check if it matches any output pattern
            for (pattern in filter.patterns) {
                if (Minimatch.make(pattern).match(query)) {
                    return true;  // Matches at least one pattern
                }
            }
            return false;  // Doesn't match any pattern
        }

        // Query is a pattern - would need pattern intersection check
        // For now, conservatively return true
        return true;
    }

    static function getExtension(path:String):Null<String> {
        var dot = path.lastIndexOf('.');
        if (dot == -1 || dot == path.length - 1) return null;
        var ext = path.substring(dot + 1).toLowerCase();
        // Ignore if extension contains wildcard
        if (ext.indexOf('*') != -1) return null;
        return ext;
    }
}
```

#### Step 3: Modify Router.getResults() to use filtering

Location: `src/whet/route/Router.hx`

```haxe
function getResults(mainFilters:Filters, results:Array<RouteResult>):Promise<Array<RouteResult>> {
    return new Promise((res, rej) -> {
        var allRouteProms = [];

        // Determine if the query is a specific file or a pattern
        var queryPattern = mainFilters.getQueryPattern();
        var queryIsPattern = queryPattern != null &&
            (queryPattern.indexOf('*') != -1 || queryPattern.indexOf('?') != -1);

        for (route in routes) {
            var routeFilters = mainFilters.clone();
            var possible = if (route.routeUnder.isDir()) routeFilters.step(route.routeUnder)
                else routeFilters.finalize(route.routeUnder);

            if (!possible) continue;

            // NEW: Output filter check
            if (route.source is AnyStone) {
                var stone:AnyStone = cast route.source;
                var remainingQuery = routeFilters.getRemainingQuery();
                if (!OutputFilterMatcher.couldMatch(remainingQuery, stone.outputFilter, queryIsPattern)) {
                    continue;  // Skip this Stone entirely
                }
            }

            // ... rest of existing logic
        }
    });
}
```

#### Step 4: Add outputFilter to relevant Stones

(Skipped, the Stone files are in a different project.)

#### Step 5: Router computes combined outputFilter

```haxe
class Router {
    public var outputFilter(get, null):Null<OutputFilter>;

    function get_outputFilter():Null<OutputFilter> {
        // Combine filters from all routes
        var allExtensions = new Array<String>();
        var allPatterns = new Array<String>();
        var hasUnfiltered = false;

        for (route in routes) {
            var childFilter = if (route.source is AnyStone)
                (cast route.source:AnyStone).outputFilter
            else if (route.source is Router)
                (cast route.source:Router).outputFilter
            else null;

            if (childFilter == null) {
                hasUnfiltered = true;
                break;  // Can't filter if any child is unfiltered
            }

            if (childFilter.extensions != null)
                for (ext in childFilter.extensions)
                    if (!allExtensions.contains(ext)) allExtensions.push(ext);

            if (childFilter.patterns != null)
                for (p in childFilter.patterns) {
                    // Prepend route prefix to pattern
                    var prefixed = Path.posix.join(route.routeUnder, p);
                    allPatterns.push(prefixed);
                }
        }

        if (hasUnfiltered) return null;
        return {
            extensions: allExtensions,
            patterns: allPatterns.length > 0 ? allPatterns : null
        };
    }
}
```

### Pattern Matching Considerations

**For specific file queries (most common in dev server):**
- Query: `audio/ogg/n_1.ogg`
- Check extension: `ogg`
- Check patterns: does `n_1.ogg` match `multiatlas_*.png`? No → skip

**For pattern queries:**
- Query: `**/*.png`
- Extension check: `png` matches some Stones
- Pattern intersection is complex, so conservatively include matching Stones
- Future optimization: implement pattern intersection check

**Edge cases:**
- Query with no extension: `README` → can't filter by extension
- Query is pure pattern: `**/*` → can't filter at all
- Stone has no filter: conservatively include it

### Expected Impact

For audio file queries:
- Before: Enumerate assetsOpt, assetsLossy, atlasFormats, audioRouter
- After: Skip image Stones, only enumerate audioRouter

For the 75 audio files case:
- Each request skips ~90% of the Stone tree
- Estimated: 200ms → 20-30ms per request

Combined with Optimization 1:
- Mtime cache: 200ms → 60-80ms
- Output filtering: 60-80ms → 10-20ms (for audio queries)

---

## Implementation Order

### Phase 1: Mtime Hash Cache (1-2 hours)
1. Create `HashCache.hx`
2. Modify `SourceHash.fromFile()`
3. Add persistence and shutdown hook
4. Test with existing project

### Phase 2: Output Filter Infrastructure (2-3 hours)
1. Add `OutputFilter` typedef and `outputFilter` field to Stone
2. Create `OutputFilterMatcher` utility
3. Modify `Router.getResults()` to check filters
4. Add `outputFilter` getter to Router

### Phase 3: Annotate Stones (1 hour)
1. Add outputFilter to SharpStone
2. Add outputFilter to ScryMultiAtlas
3. Add outputFilter to OxiPng, AudioDb, other relevant Stones
4. Test with audio file queries

### Phase 4: Validation & Tuning
1. Profile to verify improvements
2. Adjust pattern matching logic if needed
3. Add more Stone annotations as discovered

---

## Open Questions

1. **Pattern intersection**: For pattern queries like `**/*.png`, should we implement proper glob intersection, or is conservative matching acceptable?

2. **Dynamic output filters**: Some Stones might have outputs that depend on runtime config. Should `outputFilter` be a function instead of a static value?

3. **Cache invalidation**: Should `HashCache` have a max size or TTL? Old entries for deleted files will accumulate.

4. **Router filter caching**: Computing Router's combined `outputFilter` on every access might be slow. Cache it and invalidate when routes change?
