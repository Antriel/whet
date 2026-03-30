package whet.profiler;

import whet.profiler.Span.SpanOp;

class SpanStats {

    final data:Map<String, StatEntry> = new Map();

    public function new() { }

    public function getEstimate(stoneId:String, op:SpanOp<Dynamic>):Float {
        var entry = data.get('$stoneId:$op');
        return if (entry != null) entry.lastDuration else 0;
    }

    public function update(stoneId:String, op:SpanOp<Dynamic>, duration:Float):Void {
        var key = '$stoneId:$op';
        var entry = data.get(key);
        if (entry == null) {
            data.set(key, { lastDuration: duration, totalDuration: duration, count: 1 });
        } else {
            entry.lastDuration = duration;
            entry.totalDuration += duration;
            entry.count++;
        }
    }

    @:keep public function getSummary():Dynamic {
        var result:haxe.DynamicAccess<Dynamic> = new haxe.DynamicAccess();
        for (key => entry in data) {
            result.set(key, {
                lastDuration: entry.lastDuration,
                avgDuration: entry.totalDuration / entry.count,
                count: entry.count
            });
        }
        return result;
    }

}

typedef StatEntry = {

    var lastDuration:Float;
    var totalDuration:Float;
    var count:Int;

}
