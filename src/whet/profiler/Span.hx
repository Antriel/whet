package whet.profiler;

class Span<T> {

    public final id:Int;
    public final parentId:Null<Int>;
    public final stone:String;
    public final operation:SpanOp<T>;
    public final startTime:Float;
    public var endTime:Float;
    public var duration:Float;
    public var estimatedDuration:Float;
    public var metadata:T;
    public var status:SpanStatus;

    public function new(id:Int, parentId:Null<Int>, stone:String, op:SpanOp<T>, startTime:Float,
            ?metadata:T) {
        this.id = id;
        this.parentId = parentId;
        this.stone = stone;
        this.operation = op;
        this.startTime = startTime;
        this.metadata = metadata;
        this.estimatedDuration = 0;
        this.status = Ok;
    }

}

typedef AnySpan = Span<Dynamic>;

enum SpanStatus {

    Ok;
    Error(msg:String);

}

enum SpanEventType {

    Start;
    End;

}

typedef SpanEvent = {

    final type:SpanEventType;
    final span:AnySpan;

}

/**
 * Span operation types. Abstract over String for zero JS overhead --
 * each reference compiles to a string literal via `inline`.
 */
enum abstract SpanOp<T>(String) to String {

    var LockWait:SpanOp<LockWaitMeta> = "LockWait";
    var LockHeld:SpanOp<LockHeldMeta> = "LockHeld";
    var Hash:SpanOp<HashMeta> = "Hash";
    var Generate:SpanOp<GenerateMeta> = "Generate";
    var GeneratePartial:SpanOp<GeneratePartialMeta> = "GeneratePartial";
    var DependencyResolve:SpanOp<DepResolveMeta> = "DependencyResolve";
    var CacheWrite:SpanOp<CacheWriteMeta> = "CacheWrite";
    var List:SpanOp<ListMeta> = "List";
    var Serve:SpanOp<ServeMeta> = "Serve";

}

/** Metadata types per span operation. */
typedef LockWaitMeta = {

    var ?queuePosition:Int;
    var ?queueLength:Int;

}

typedef LockHeldMeta = {

    var ?cacheResult:String;

}

typedef HashMeta = {

    var ?hashHex:String;
    var ?dependencyCount:Int;

}

typedef GenerateMeta = {

    var ?outputCount:Int;
    var ?totalBytes:Int;

}

typedef GeneratePartialMeta = {

    var ?sourceId:String;
    var ?outputBytes:Int;

}

typedef DepResolveMeta = {

    var ?dependencyIds:Array<String>;

}

typedef CacheWriteMeta = {

    var ?strategy:String;
    var ?entryCount:Int;

}

typedef ListMeta = {

    var ?resultCount:Null<Int>;

}

typedef ServeMeta = {

    var ?method:String;
    var ?path:String;
    var ?statusCode:Int;
    var ?responseBytes:Int;

}
