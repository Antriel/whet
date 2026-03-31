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
        var stoneToTid = new haxe.ds.StringMap<Int>();
        var nextTid = 1;
        var events:Array<Dynamic> = [];

        for (span in spans) {
            if (!stoneToTid.exists(span.stone)) {
                stoneToTid.set(span.stone, nextTid++);
            }
            events.push({
                ph: "X",
                name: (span.operation:String) + " " + span.stone,
                cat: "whet",
                ts: baseEpochUs + (span.startTime * 1000 - basePerfUs),
                dur: span.duration * 1000,
                pid: 1,
                tid: stoneToTid.get(span.stone),
                args: span.metadata
            });
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
