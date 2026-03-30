package whet.profiler;

import whet.profiler.Span.AnySpan;

class SpanRecorder {

    public final maxSize:Int;
    public var totalCount(default, null):Int = 0;

    final buffer:haxe.ds.Vector<AnySpan>;
    var writeIndex:Int = 0;

    public function new(maxSize:Int) {
        this.maxSize = maxSize;
        this.buffer = new haxe.ds.Vector(maxSize);
    }

    public function record(span:AnySpan):Void {
        buffer[writeIndex % maxSize] = span;
        writeIndex++;
        totalCount++;
    }

    /** Returns all recorded spans in chronological order. */
    @:keep public function getSpans():Array<AnySpan> {
        var count = writeIndex < maxSize ? writeIndex : maxSize;
        var result = new Array<AnySpan>();
        result.resize(count);
        var start = if (writeIndex < maxSize) 0 else writeIndex % maxSize;
        for (i in 0...count) {
            result[i] = buffer[(start + i) % maxSize];
        }
        return result;
    }

    /** Returns spans recorded since the given span ID (exclusive). */
    @:keep public function getSpansSince(sinceId:Int):Array<AnySpan> {
        var all = getSpans();
        var result:Array<AnySpan> = [];
        for (span in all) {
            if (span.id > sinceId) result.push(span);
        }
        return result;
    }

}
