package whet.profiler;

import js.lib.Promise;
import whet.profiler.Span;

class Profiler {

    public final recorder:SpanRecorder;
    public final stats:SpanStats;

    final listeners:Array<SpanEvent->Void> = [];
    final context:AsyncLocalStorage<AnySpan>;

    var nextSpanId:Int = 0;

    public function new(?config:ProfilerConfig) {
        var maxSpans = if (config != null && config.maxSpans != null) config.maxSpans else 10000;
        recorder = new SpanRecorder(maxSpans);
        stats = new SpanStats();
        context = new AsyncLocalStorage();
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

    /** Subscribe to span events. Returns unsubscribe function. */
    @:keep public function subscribe(listener:SpanEvent->Void):Void->Void {
        listeners.push(listener);
        return () -> listeners.remove(listener);
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
