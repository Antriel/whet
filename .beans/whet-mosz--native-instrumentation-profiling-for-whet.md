---
# whet-mosz
title: Native Instrumentation & Profiling for Whet
status: draft
type: epic
priority: high
created_at: 2026-03-28T06:46:54Z
updated_at: 2026-03-28T09:40:01Z
---

Add optional profiling to Whet: track stone generation timing, cache hits/misses, dependency chains, and generation reasons. Support live streaming for long-lived services. Negligible overhead when disabled.

---

## Design Document: Whet Native Instrumentation

### Goals
1. **Precise timing** of every stone operation: generation, hash computation, cache lookups, dependency resolution, lock wait time
2. **Cache observability**: hit/miss, reason for miss, durability evictions
3. **Causality tracking**: why was a stone generated? (HTTP request, dependency of X, explicit `refreshSource`, CLI command)
4. **Live streaming** for long-lived services (dev servers) -- subscribe to span start and end events in real time, including estimated duration from historical data
5. **Export** for post-hoc analysis and chart generation (JSON, Chrome Tracing format)
6. **Negligible overhead** when disabled -- no allocations, no timekeeping, no function calls

### Architecture Overview

```
Project
  +-- Profiler (optional, null when disabled)
        |-- SpanRecorder  -- collects Span objects in ring buffer (Vector)
        |-- SpanStats     -- incremental per-{stoneId, op} timing stats
        |-- EventBus      -- synchronous emit to subscribers (start + end events)
        +-- ExportAdapter  -- JSON / Chrome Trace / Custom
        +-- AsyncLocalStorage context -- automatic parent-child span nesting
```

#### Core concept: **Spans**

A Span represents a timed operation with metadata. Spans form a tree via parent references. Modeled after OpenTelemetry's span concept (familiar, proven, tools exist) but kept minimal.

```haxe
// In whet/profiler/Span.hx
class Span<T> {
    public final id:Int;                   // incrementing int, cheap
    public final parentId:Null<Int>;
    public final stone:String;             // stone.id
    public final operation:SpanOp<T>;
    public final startTime:Float;          // performance.now() for ms precision
    public var endTime:Float;
    public var duration:Float;             // endTime - startTime (ms)
    public var estimatedDuration:Float;    // from historical stats, set on start
    public var metadata:T;                 // operation-specific, type-safe via GADT
    public var status:SpanStatus;          // Ok, Error
}

typedef AnySpan = Span<Dynamic>;

enum SpanStatus { Ok; Error(msg:String); }
```

#### SpanOp -- GADT via abstract enum over String

Using a parameterized abstract over String gives us type-safe metadata at callsites with zero JS overhead (each reference compiles to a string literal via `inline`):

```haxe
abstract SpanOp<T>(String) to String {
    public static inline var LockWait:SpanOp<LockWaitMeta> = cast "LockWait";
    public static inline var LockHeld:SpanOp<LockHeldMeta> = cast "LockHeld";
    public static inline var Hash:SpanOp<HashMeta> = cast "Hash";
    public static inline var Generate:SpanOp<GenerateMeta> = cast "Generate";
    public static inline var GeneratePartial:SpanOp<GeneratePartialMeta> = cast "GeneratePartial";
    public static inline var DependencyResolve:SpanOp<DepResolveMeta> = cast "DependencyResolve";
    public static inline var CacheWrite:SpanOp<CacheWriteMeta> = cast "CacheWrite";
    public static inline var List:SpanOp<ListMeta> = cast "List";
    public static inline var Serve:SpanOp<ServeMeta> = cast "Serve";

    public inline function toString():String return this;
}
```

If Haxe's type system doesn't cooperate with GADT unification on abstract enums (e.g. `SpanOp<GenerateMeta>` not unifying with `SpanOp<Dynamic>` for storage), we fall back to untyped `Dynamic` metadata. The abstract-over-String pattern is still valuable on its own for zero-overhead op names. See "Open question" at end.

#### Metadata typedefs per operation

```haxe
typedef LockWaitMeta = { ?queuePosition:Int, ?queueLength:Int };
typedef LockHeldMeta = { ?cacheResult:String }; // "hit", "miss", "partial"
typedef HashMeta = { ?hashHex:String, ?dependencyCount:Int };
typedef GenerateMeta = { ?outputCount:Int, ?totalBytes:Int, ?cacheResult:String };
typedef GeneratePartialMeta = { ?sourceId:String, ?outputBytes:Int };
typedef DepResolveMeta = { ?dependencyIds:Array<String> };
typedef CacheWriteMeta = { ?strategy:String, ?entryCount:Int };
typedef ListMeta = { ?resultCount:Null<Int> };
typedef ServeMeta = { ?method:String, ?path:String, ?statusCode:Int, ?responseBytes:Int };
```

Cache hit/miss is recorded as metadata on the **LockHeld** or **Generate** span (the `cacheResult` field) rather than as a separate CacheLookup span -- the cache check itself is synchronous (a Map lookup + hash comparison) and making it a separate span would add noise without value.

### Design Decisions

#### 1. Toggle mechanism -- Null Profiler pattern

```haxe
// In Project.hx
public var profiler:Null<Profiler> = null;
```

```haxe
// In Stone.hx -- two APIs:

// Primary: withSpan wraps an async operation, manages ALS context + timing
inline function withSpan<R>(op:SpanOp, fn:Void->Promise<R>, ?meta:Dynamic):Promise<R> {
    return if (project.profiler != null) project.profiler.withSpan(this, op, fn, meta) else fn();
}

// Secondary: manual start/end for spans where you can't wrap a function (LockWait)
inline function startSpan(op:SpanOp, ?meta:Dynamic):Null<AnySpan> {
    return if (project.profiler != null) project.profiler.startSpan(this, op, meta) else null;
}
inline function endSpan(span:Null<AnySpan>):Void {
    if (span != null) project.profiler.endSpan(span);
}
```

When `profiler` is null (default), the `inline` expands to a null check at each callsite -- no function call overhead, no allocation. Note: Haxe's DCE cannot eliminate the null check since `project.profiler` is a runtime value, but the `inline` avoids any function call overhead, and a single null check per operation is negligible.

**Enabled via ProjectConfig:**
```haxe
var ?profiler:ProfilerConfig;

typedef ProfilerConfig = {
    var ?maxSpans:Int;          // Ring buffer size, default 10000
    var ?streamToLog:Bool;      // Emit spans as structured log lines
    var ?retainCompleted:Bool;  // Keep spans after streaming (default false for long-lived)
}
```

**Or enabled at runtime** (for dev tools to toggle):
```haxe
// In Project.hx
public function enableProfiling(?config:ProfilerConfig):Void {
    if (profiler == null) profiler = new Profiler(config);
}
public function disableProfiling():Void {
    profiler = null;
}
```

Runtime toggle is safe because the null check is per-operation. A race (toggling mid-generation) just means a span might be missed, never a crash.

#### 2. Memory management -- Ring buffer with Vector

For long-lived services, unbounded span storage is a memory leak. Solution: **ring buffer** using `haxe.ds.Vector` (abstract over `js.Syntax.construct(Array, length)` in JS -- pre-allocates, avoids growth).

```haxe
class SpanRecorder {
    final buffer:haxe.ds.Vector<AnySpan>;
    final maxSize:Int;
    var writeIndex:Int = 0;
    var totalCount:Int = 0;    // Total ever recorded (for stats)

    public function new(maxSize:Int) {
        this.maxSize = maxSize;
        this.buffer = new haxe.ds.Vector(maxSize);
    }

    public function record(span:AnySpan):Void {
        buffer[writeIndex % maxSize] = span;
        writeIndex++;
        totalCount++;
    }
}
```

- Default 10,000 spans (~2-5MB depending on metadata). More than enough for analysis, auto-evicts old entries.
- `retainCompleted: false` -- when streaming is active, spans are emitted to subscribers and then only kept in the ring buffer. Subscribers that need history maintain their own storage.
- Export snapshots the current buffer state.

#### 3. Live streaming -- Synchronous EventBus with start + end events

Subscribers receive events for both span **start** and span **end**. Start events enable showing in-flight operations (e.g., "Building game.js...") with estimated duration from historical stats.

```haxe
enum SpanEventType { Start; End; }

typedef SpanEvent = {
    final type:SpanEventType;
    final span:AnySpan;
}

class Profiler {
    final recorder:SpanRecorder;
    final stats:SpanStats;
    final listeners:Array<SpanEvent->Void> = [];
    final context:AsyncLocalStorage<AnySpan>;

    public function subscribe(listener:SpanEvent->Void):Void->Void {
        listeners.push(listener);
        return () -> listeners.remove(listener);
    }

    function emit(type:SpanEventType, span:AnySpan):Void {
        var event = { type: type, span: span };
        for (l in listeners) l(event);
    }
}
```

Why synchronous callbacks instead of Node EventEmitter:
- No extra dependency
- Subscribers get spans immediately (no microtask delay) -- critical for live UIs
- Simpler to reason about ordering
- If a subscriber needs async work, they can buffer internally

#### 4. Causality tracking -- AsyncLocalStorage with `withSpan`

The key insight: **the parent span tells you "why"**.

When `Stone.getSource()` is called from within another stone's `generateSource()` (dependency resolution), the parent span is `DependencyResolve` on the parent stone. When called from an HTTP handler, the parent span is `Serve`. When called from CLI, there is no parent (root span).

**`withSpan` is the primary API** because AsyncLocalStorage requires wrapping a function call with `context.run()` to scope the context. There is no safe "push/pop" alternative -- `enterWith()` exists in Node.js but is explicitly discouraged because it doesn't scope properly with async code (a `.then()` firing between push and pop sees the wrong context).

Verified behavior: AsyncLocalStorage captures context at `.then()` registration time. So in:
```javascript
als.run(lockHeldSpan, () => {
    withSpan('Hash', () => doHash())
        .then(hash => {
            // ALS store = lockHeldSpan (correct! back to parent)
        });
});
```
...the continuation after `withSpan` returns to the parent's context automatically. This means nested `withSpan` calls in `.then()` chains produce correct parent-child trees with no manual context management.

```haxe
// In Profiler -- primary API
public function withSpan<T, R>(stone:AnyStone, op:SpanOp<T>, fn:Void->Promise<R>, ?meta:T):Promise<R> {
    var parent = context.getStore();
    var span = new Span(nextId(), parent?.id, stone.id, op, perfNow(), meta);
    span.estimatedDuration = stats.getEstimate(stone.id, op);
    emit(Start, span);
    return context.run(span, () -> {
        return fn().then(result -> {
            span.endTime = perfNow();
            span.duration = span.endTime - span.startTime;
            span.status = Ok;
            recorder.record(span);
            stats.update(stone.id, op, span.duration);
            emit(End, span);
            return result;
        }).catchError(err -> {
            span.endTime = perfNow();
            span.duration = span.endTime - span.startTime;
            span.status = Error(Std.string(err));
            recorder.record(span);
            emit(End, span);
            return Promise.reject(err);
        });
    });
}

// Secondary API -- for LockWait where no function can be wrapped.
// Does NOT set ALS context (nothing meaningful runs during the wait).
public function startSpan<T>(stone:AnyStone, op:SpanOp<T>, ?meta:T):Span<T> {
    var parent = context.getStore();
    var span = new Span(nextId(), parent?.id, stone.id, op, perfNow(), meta);
    span.estimatedDuration = stats.getEstimate(stone.id, op);
    emit(Start, span);
    return span;
}

public function endSpan(span:AnySpan):Void {
    span.endTime = perfNow();
    span.duration = span.endTime - span.startTime;
    span.status = Ok;
    recorder.record(span);
    stats.update(span.stone, span.operation, span.duration);
    emit(End, span);
}
```

**SpanStats** -- incremental historical timing for estimated durations:

```haxe
// Tracks last/avg duration per {stoneId, op} key
class SpanStats {
    // Map key: "stoneId:op"
    final data:Map<String, { lastDuration:Float, totalDuration:Float, count:Int }>;

    public function getEstimate(stoneId:String, op:SpanOp<Dynamic>):Float {
        var entry = data.get('$stoneId:$op');
        return if (entry != null) entry.lastDuration else 0;
    }

    public function update(stoneId:String, op:SpanOp<Dynamic>, duration:Float):Void {
        var key = '$stoneId:$op';
        var entry = data.get(key);
        if (entry == null) { data.set(key, { lastDuration: duration, totalDuration: duration, count: 1 }); }
        else { entry.lastDuration = duration; entry.totalDuration += duration; entry.count++; }
    }
}
```

This enables the build progress UI to show "Building game.js... 3.2s (avg: 5.1s)" by reading `estimatedDuration` from the Start event.

#### 5. Instrumentation points -- complete map

All instrumentation is in two files: `Stone.hx` and `BaseCache.hx`. Each span, where it's instrumented, and which API it uses:

| Span | File | API | ALS parent |
|------|------|-----|------------|
| **LockWait** | `Stone.acquire()`, when `locked==true` | `startSpan`/`endSpan` | whatever called acquire (e.g. from BaseCache.get) |
| **LockHeld** | `Stone.acquire()`, wrapping `run` callback | `withSpan` | whatever called acquire |
| **Hash** | `BaseCache.get()`, wrapping `stone.finalMaybeHash()` | `withSpan` | LockHeld |
| **Generate** | `BaseCache.get()`, wrapping `stone.generateSource(hash)` | `withSpan` | LockHeld |
| **GeneratePartial** | `BaseCache.getPartial()`, wrapping `stone.generatePartialSource()` | `withSpan` | LockHeld |
| **DependencyResolve** | `Stone.generateSource()`, wrapping `Promise.all(deps)` | `withSpan` | Generate |
| **CacheWrite** | `BaseCache.get()`, wrapping `set(src)` | `withSpan` | LockHeld |
| **List** | `BaseCache.completePartialEntry()`, wrapping `stone.list()` | `withSpan` | LockHeld |
| **Serve** | Consumer code (UwsServerStone request handler) | `withSpan` | none (root span) |

Cache hit/miss is not a separate span -- the synchronous Map lookup result is recorded as `cacheResult` metadata on the **LockHeld** span (or **Generate** if a miss triggers generation).

**Resulting span tree for a cache miss:**

```
Serve (HTTP request for game.js)
  └─ LockHeld {cacheResult: "miss"}
       ├─ Hash (finalMaybeHash + finalizeHash)
       ├─ Generate (generateSource)
       │    ├─ DependencyResolve
       │    │    └─ [recursive: LockHeld for each dependency stone]
       │    └─ [actual generate() / list()+generatePartial() call]
       └─ CacheWrite (set)
```

**For a cache hit:**
```
LockHeld {cacheResult: "hit"}
  └─ Hash (finalMaybeHash)
```

**Instrumented `Stone.acquire()` mockup:**

```haxe
@:allow(whet) final function acquire<T>(run:Void->Promise<T>):Promise<T> {
    if (locked) {
        var waitSpan = startSpan(LockWait, {queuePosition: lockQueue.length, queueLength: lockQueue.length + 1});
        var deferredRes:T->Void;
        var deferredRej:Dynamic;
        var deferred = new Promise((res, rej) -> { deferredRes = res; deferredRej = rej; });
        lockQueue.push({
            run: () -> {
                endSpan(waitSpan);
                return withSpan(LockHeld, run);
            },
            res: deferredRes, rej: deferredRej
        });
        return deferred;
    } else {
        locked = true;
        function runNext() {
            if (lockQueue.length > 0) {
                var queued = lockQueue.shift();
                queued.run().then(queued.res).catchError(queued.rej).finally(runNext);
            } else locked = false;
        }
        return withSpan(LockHeld, run).finally(runNext);
    }
}
```

**Instrumented `BaseCache.get()` mockup (structural sketch):**

```haxe
public function get(stone:AnyStone, durability, check):Promise<Source> {
    return stone.acquire(() ->
        stone.withSpan(Hash, () -> stone.finalMaybeHash())
        .then(hash -> {
            // Sync cache check
            var values = cache.get(key(stone));
            var value = if (values != null) Lambda.find(values, v -> v.hash.equals(hash)) else null;
            // ... durability checks (same as current) ...

            return if (value != null && src.complete)
                Promise.resolve(src) // cache hit -- cacheResult metadata set on LockHeld span
            else if (value != null && !src.complete)
                completePartialEntry(stone, value, hash) // partial hit
            else
                stone.withSpan(Generate, () -> stone.generateSource(hash))
                .then(src -> stone.withSpan(CacheWrite, () -> set(src))
                .then(val -> source(stone, val))); // cache miss
        })
    );
}
```

#### 6. Export formats

**JSON export** -- array of spans with parent references:
```javascript
project.profiler.export("json")
// -> { spans: [...], meta: { startTime, endTime, stoneCount, totalGenerations, cacheHitRate } }
```

**Chrome Trace format** -- for chrome://tracing visualization:
```javascript
project.profiler.export("trace")
// -> { traceEvents: [{ ph: "X", name: "Generate game-haxe-build", ts: ..., dur: ..., ... }] }
```

Chrome Trace uses microseconds from epoch. Conversion from `performance.now()` (monotonic ms):
- Capture base timestamps at Profiler construction: `baseEpochUs = Date.now() * 1000`, `basePerfUs = performance.now() * 1000`
- Per span: `ts = baseEpochUs + (span.startTime * 1000 - basePerfUs)`

This gives flame charts for free in Chrome DevTools.

**Summary stats** (derived from SpanStats, available live):
```javascript
project.profiler.getSummary()
// -> {
//     byStone: { "game-haxe-build": { generates: 5, avgDuration: 3200, cacheHits: 12, lastDuration: 4100 } },
//     byOperation: { Generate: { count: 20, totalMs: 45000 }, Hash: { count: 50, totalMs: 200 } },
//     cacheHitRate: 0.6
// }
```

#### 7. Integration with Scry (long-lived dev server)

The existing Scry plugin architecture works. A new `ProfilerPlugin` for ScryStone.

**Prerequisite:** ScryStone needs to store `clientRegistry` as an instance property (currently it's a local in `serve()`):
```javascript
// In ScryStone.serve():
this.clientRegistry = new ClientRegistry();
// instead of: const clientRegistry = new ClientRegistry();
```

Then the plugin can access it via type assertion:

```javascript
// scry/whetstones/plugins/ProfilerPlugin.mjs
export default class ProfilerPlugin {
    constructor(project) { this.project = project; }

    registerRoutes(app, stone, sendJson) {
        if (!(stone instanceof ScryStone))
            throw new Error("ProfilerPlugin requires ScryStone");

        // REST endpoints
        stone.registerApiRoute(app, '/api/profiler/summary', (res) =>
            sendJson(res, this.project.profiler?.getSummary() ?? { enabled: false }));

        stone.registerApiRoute(app, '/api/profiler/export', (res) => {
            const format = /* parse query param */ 'trace';
            sendJson(res, this.project.profiler?.export(format) ?? {});
        });

        stone.registerApiRoute(app, '/api/profiler/spans', (res) => {
            const since = /* parse query param */;
            sendJson(res, this.project.profiler?.getSpansSince(since) ?? []);
        });

        // Subscribe to profiler and broadcast span events via WS
        if (this.project.profiler) {
            this.project.profiler.subscribe(event => {
                stone.clientRegistry.broadcastToType('editor', {
                    type: 'profiler:span',
                    event: event.type, // 'start' or 'end'
                    data: event.span
                });
            });
        }
    }

    registerCommands(registry) {
        registry.on('profiler:status', () => ({
            enabled: this.project.profiler != null,
            spanCount: this.project.profiler?.recorder.totalCount ?? 0,
            bufferSize: this.project.profiler?.recorder.maxSize ?? 0
        }));

        registry.on('profiler:toggle', (data) => {
            if (this.project.profiler) this.project.disableProfiling();
            else this.project.enableProfiling(data?.config);
            return { enabled: this.project.profiler != null };
        });

        registry.on('profiler:snapshot', () =>
            this.project.profiler?.export('json') ?? { enabled: false });
    }
}
```

**Browser-side build progress plugin:**

The existing `build-error-plugin.mjs` (at `libraries/shards.client/whet/plugins/`) fetches `/api/build-status` when a script fails to load. With profiling, a companion `build-progress-plugin.mjs` can:

1. Subscribe to profiler WebSocket events (via the Scry WS connection)
2. On receiving a `Start` event for Generate on the relevant stone, show "Building game.js..." with estimated duration from `span.estimatedDuration`
3. On receiving the `End` event, show timing breakdown: "Generated in 5.1s (hash: 20ms, deps: 1.2s, build: 3.8s, cache write: 100ms)" by collecting child spans
4. Falls back to polling `/api/profiler/spans?stone=<id>&active=true` if WS not connected

**Filtering spans by request** -- viable via parent chain:

When UwsServerStone handles an HTTP request for `game.js`, it starts a `Serve` span via `withSpan`. Everything triggered by that request (cache lookup, generation, dependency resolution) will have that Serve span as ancestor via AsyncLocalStorage context propagation. The client can request "give me all spans descended from Serve span X" -- this gives a complete per-request profile.

### Open Questions

**GADT type parameter unification**: Does `SpanOp<GenerateMeta>` unify with `SpanOp<Dynamic>` when storing `Span<Dynamic>` in the ring buffer? Needs testing. If Haxe fights us, options: (a) add `toAny():SpanOp<Dynamic>` inline cast, (b) fall back to untyped metadata with the abstract-over-String still providing zero-overhead op names.

### Resolved Questions

**Where to store data?** Ring buffer in memory (default 10K spans). Export snapshots on demand. No disk persistence needed -- profiling is ephemeral by nature. 10K spans is roughly 2-5MB, well within reason even for long-lived services.

**How to toggle with zero overhead?** Null profiler pattern. `project.profiler` is `null` by default. All instrumentation points are `inline` functions that expand to a null check at the callsite. No allocations, no function calls, no timing when disabled.

**How to handle long-lived services?** Ring buffer auto-evicts old spans. Live subscribers get spans synchronously as they start and complete. Summary stats are maintained incrementally (O(1) per span). Memory is bounded regardless of service uptime.

**Request-scoped filtering?** AsyncLocalStorage propagates a "current span" through the entire Promise `.then()` chain. Verified: context is captured at `.then()` registration time, and `context.run()` properly scopes nested calls. Every span knows its parent. Given a Serve span ID, walk descendants to get the full request profile.

**How to integrate ALS with `.then()` chains (not async/await)?** The `withSpan` pattern: `context.run(span, () -> fn().then(cleanup))`. The continuation after `withSpan().then(...)` returns to the parent context automatically. `enterWith()` is not viable -- it doesn't scope with async code. Manual `startSpan`/`endSpan` is reserved for LockWait where nothing runs during the span.

### Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| AsyncLocalStorage overhead | Benchmarked at <1% in Node.js; used by Node internals. Can fall back to explicit context passing if needed |
| Span metadata allocation when profiling is on | Keep metadata objects small. GADT typedefs enforce structure. Pool if needed |
| Ring buffer losing important spans | Configurable size. Export before buffer wraps. Subscribers get all spans in real time (start + end) |
| GADT type params not unifying on abstract enum | Fall back to `Dynamic` metadata; abstract-over-String still gives zero-overhead op names |

### Implementation Plan

- [x] Phase 1: Core Profiler (Whet-side, Haxe) — see whet-j8n9
- [ ] Phase 2: Export and Analysis
  - [ ] JSON export format
  - [ ] Chrome Trace export format (with epoch microsecond timestamp conversion)
  - [ ] Summary stats aggregation (from SpanStats)
  - [ ] CLI `--profile` flag and `profile` command (export on exit)
- [ ] Phase 3: Live Streaming and Scry Integration
  - [ ] Expose `ScryStone.clientRegistry` as instance property
  - [ ] `ProfilerPlugin` for ScryStone (REST endpoints + WS broadcast, instanceof assertion)
  - [ ] Browser `build-progress-plugin.mjs` (WS subscription, estimated duration, timing breakdown)
  - [ ] Per-request span filtering via parent chain
  - [ ] Runtime toggle via Scry commands (`profiler:toggle`, `profiler:status`)
