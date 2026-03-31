package whet.profiler;

import js.lib.Promise;
import whet.profiler.Span;

class Profiler {

    public final recorder:SpanRecorder;
    public final stats:SpanStats;

    final listeners:Array<SpanEvent->Void> = [];
    final context:AsyncLocalStorage<AnySpan>;
    final baseEpochUs:Float;
    final basePerfUs:Float;

    var nextSpanId:Int = 0;

    public function new(?config:ProfilerConfig) {
        var maxSpans = if (config != null && config.maxSpans != null) config.maxSpans else 10000;
        recorder = new SpanRecorder(maxSpans);
        stats = new SpanStats();
        context = new AsyncLocalStorage();
        baseEpochUs = js.lib.Date.now() * 1000;
        basePerfUs = perfNow() * 1000;
    }

    /** Primary API: wraps an async operation with timing and ALS context. */
    public function withSpan<T, R>(stone:whet.Stone.AnyStone, op:SpanOp<T>, fn:Void->Promise<R>,
            ?meta:T):Promise<R> {
        var parent = context.getStore();
        var span = new Span(nextSpanId++, parent != null ? parent.id : null, stone.id, op, perfNow(), meta);
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

    /** Secondary API: manual start for spans where no function can be wrapped (e.g. LockWait). */
    public function startSpan<T>(stone:whet.Stone.AnyStone, op:SpanOp<T>, ?meta:T):AnySpan {
        var parent = context.getStore();
        var span = new Span(nextSpanId++, parent != null ? parent.id : null, stone.id, op, perfNow(), meta);
        span.estimatedDuration = stats.getEstimate(stone.id, op);
        emit(Start, span);
        return span;
    }

    /** Complete a manually started span. */
    public function endSpan(span:AnySpan):Void {
        span.endTime = perfNow();
        span.duration = span.endTime - span.startTime;
        span.status = Ok;
        recorder.record(span);
        stats.update(span.stone, span.operation, span.duration);
        emit(End, span);
    }

    /** Returns the current span from AsyncLocalStorage context, or null if none. */
    public function getCurrentSpan():Null<AnySpan> {
        return context.getStore();
    }

    /** Subscribe to span events. Returns unsubscribe function. */
    @:keep public function subscribe(listener:SpanEvent->Void):Void->Void {
        listeners.push(listener);
        return () -> listeners.remove(listener);
    }

    /** Export spans in the given format ("json" or "trace"). Defaults to "json". */
    @:keep @:native("export") public function exportProfile(format:String):Dynamic {
        return if (format == "trace") exportChromeTrace() else exportJson();
    }

    /** Return spans recorded since the given span ID (exclusive). */
    @:keep public function getSpansSince(sinceId:Int):Array<AnySpan> {
        return recorder.getSpansSince(sinceId);
    }

    /** Return aggregated profiling summary. */
    @:keep public function getSummary():Dynamic {
        var spans = recorder.getSpans();
        var byStone:haxe.DynamicAccess<Dynamic> = new haxe.DynamicAccess();
        var byOperation:haxe.DynamicAccess<Dynamic> = new haxe.DynamicAccess();
        var cacheHits = 0;
        var cacheLookups = 0;

        for (span in spans) {
            var opKey = span.operation;
            var opEntry = byOperation.get(opKey);
            if (opEntry == null) {
                opEntry = { count: 0, totalMs: 0.0 };
                byOperation.set(opKey, opEntry);
            }
            opEntry.count++;
            opEntry.totalMs += span.duration;

            if (opKey == Generate) {
                ensureStoneEntry(byStone, span.stone);
                var entry = byStone.get(span.stone);
                entry.generates++;
                entry.totalDuration += span.duration;
                entry.avgDuration = entry.totalDuration / entry.generates;
                entry.lastDuration = span.duration;
            }

            if (span.metadata != null) {
                var meta = span.metadata;
                if (meta.cacheResult != null) {
                    cacheLookups++;
                    if (meta.cacheResult == "hit") {
                        cacheHits++;
                        ensureStoneEntry(byStone, span.stone);
                        byStone.get(span.stone).cacheHits++;
                    }
                }
            }
        }

        return {
            byStone: (byStone:Dynamic),
            byOperation: (byOperation:Dynamic),
            cacheHitRate: if (cacheLookups > 0) cacheHits / cacheLookups else 0.0
        };
    }

    function exportJson():Dynamic {
        var spans = recorder.getSpans();
        var spanData:Array<Dynamic> = [for (s in spans) serializeSpan(s)];

        var stoneSet = new haxe.ds.StringMap<Bool>();
        var generateCount = 0;
        var cacheHits = 0;
        var cacheLookups = 0;

        for (span in spans) {
            stoneSet.set(span.stone, true);
            if (span.operation == Generate) generateCount++;
            if (span.metadata != null) {
                var meta = span.metadata;
                if (meta.cacheResult != null) {
                    cacheLookups++;
                    if (meta.cacheResult == "hit") cacheHits++;
                }
            }
        }

        var stoneCount = 0;
        for (_ in stoneSet) stoneCount++;

        return {
            spans: spanData,
            meta: {
                spanCount: spans.length,
                stoneCount: stoneCount,
                totalGenerations: generateCount,
                cacheHitRate: if (cacheLookups > 0) cacheHits / cacheLookups else 0.0
            }
        };
    }

    function exportChromeTrace():Dynamic {
        var spans = recorder.getSpans();
        // Build lookup and children map
        var spanById = new Map<Int, AnySpan>();
        for (span in spans) spanById.set(span.id, span);

        var childrenOf = new Map<Int, Array<AnySpan>>();
        var roots:Array<AnySpan> = [];
        for (span in spans) {
            var pid = span.parentId;
            if (pid == null || !spanById.exists(pid)) {
                roots.push(span);
            } else {
                if (!childrenOf.exists(pid)) childrenOf.set(pid, []);
                childrenOf.get(pid).push(span);
            }
        }

        // Assign tids using concurrent-lane decomposition.
        // Sequential children share the parent's tid (lane 0); concurrent
        // siblings that overlap in time get new tids. This ensures no two
        // X events on the same tid ever partially overlap.
        var spanTid = new Map<Int, Int>();
        var nextTid = 1;
        function assignTids(span:AnySpan, tid:Int):Void {
            spanTid.set(span.id, tid);
            var children = childrenOf.get(span.id);
            if (children == null || children.length == 0) return;

            children.sort((a, b) -> Reflect.compare(a.startTime, b.startTime));

            var laneEndTimes:Array<Float> = [];
            var laneTids:Array<Int> = [];

            for (child in children) {
                var lane = -1;
                for (i in 0...laneEndTimes.length) {
                    if (laneEndTimes[i] <= child.startTime) {
                        lane = i;
                        break;
                    }
                }
                if (lane == -1) {
                    lane = laneEndTimes.length;
                    laneTids.push(lane == 0 ? tid : nextTid++);
                    laneEndTimes.push(child.endTime);
                } else {
                    laneEndTimes[lane] = child.endTime;
                }
                assignTids(child, laneTids[lane]);
            }
        }

        roots.sort((a, b) -> Reflect.compare(a.startTime, b.startTime));
        for (root in roots) assignTids(root, nextTid++);

        var events:Array<Dynamic> = [];

        // Thread name metadata events (label each tid with the first stone seen on it)
        var tidNames = new Map<Int, String>();
        for (span in spans) {
            var tid = spanTid.get(span.id);
            if (tid != null && !tidNames.exists(tid)) tidNames.set(tid, span.stone);
        }
        for (tid => name in tidNames) {
            events.push({ ph: "M", pid: 1, tid: tid, name: "thread_name", args: { name: name } });
        }

        // Span events + flow arrows for cross-tid causality
        var flowId = 0;
        for (span in spans) {
            var tid = spanTid.get(span.id);
            if (tid == null) continue;
            var ts = baseEpochUs + (span.startTime * 1000 - basePerfUs);
            events.push({
                ph: "X",
                name: (span.operation:String) + " " + span.stone,
                cat: "whet",
                ts: ts,
                dur: span.duration * 1000,
                pid: 1,
                tid: tid,
                args: span.metadata != null ? span.metadata : { }
            });
            // When a child is on a different tid than its parent, draw a flow
            // arrow so you can trace why an operation was triggered.
            if (span.parentId != null) {
                var parent = spanById.get(span.parentId);
                if (parent != null) {
                    var parentTid = spanTid.get(parent.id);
                    if (parentTid != null && parentTid != tid) {
                        var parentTs = baseEpochUs + (parent.startTime * 1000 - basePerfUs);
                        events.push({
                            ph: "s",
                            id: flowId,
                            pid: 1,
                            tid: parentTid,
                            ts: parentTs,
                            name: "trigger",
                            cat: "flow"
                        });
                        events.push({
                            ph: "f",
                            bp: "e",
                            id: flowId,
                            pid: 1,
                            tid: tid,
                            ts: ts,
                            name: "trigger",
                            cat: "flow"
                        });
                        flowId++;
                    }
                }
            }
        }

        return { traceEvents: events };
    }

    function serializeSpan(span:AnySpan):Dynamic {
        return {
            id: span.id,
            parentId: span.parentId,
            stone: span.stone,
            operation: (span.operation:String),
            startTime: span.startTime,
            endTime: span.endTime,
            duration: span.duration,
            estimatedDuration: span.estimatedDuration,
            metadata: span.metadata,
            status: switch (span.status) {
                case Ok: "ok";
                case Error(msg): "error: " + msg;
            }
        };
    }

    static function ensureStoneEntry(byStone:haxe.DynamicAccess<Dynamic>, stone:String):Void {
        if (!byStone.exists(stone)) {
            byStone.set(stone, {
                generates: 0,
                totalDuration: 0.0,
                avgDuration: 0.0,
                lastDuration: 0.0,
                cacheHits: 0
            });
        }
    }

    function emit(type:SpanEventType, span:AnySpan):Void {
        var event:SpanEvent = { type: type, span: span };
        for (l in listeners) l(event);
    }

    static inline function perfNow():Float {
        return js.Syntax.code("performance.now()");
    }

}

typedef ProfilerConfig = {

    var ?maxSpans:Int;

}

@:jsRequire("node:async_hooks", "AsyncLocalStorage")
extern class AsyncLocalStorage<T> {

    function new();

    /** Returns the current store. Undefined if called outside of an async context initialized by `run`. */
    function getStore():Null<T>;

    /** Runs a function synchronously within a context and returns its return value. */
    function run<R>(store:T, callback:Void->R):R;

}
