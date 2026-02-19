package whet.route;

@:structInit class RouteResult {

    /** Id under which this item is served by `Router`. Can be different from `sourceId`. */
    @:allow(whet.route) public var serveId(default, null):SourceId;

    /** Id under which this item is provided by the stone. */
    public final sourceId:SourceId;

    /** Stone providing this item. */
    public final source:AnyStone;

    public function get():Promise<SourceData> {
        return source.getPartialSource(sourceId).then(s -> if (s != null) s.get() else null);
    }

    /** Get the raw Buffer directly. */
    public function getData():Promise<js.node.Buffer> {
        return get().then(sd -> sd.data);
    }

    /** Get the output as a UTF-8 string. */
    public function getString():Promise<String> {
        return getData().then(d -> d.toString('utf-8'));
    }

    /** Get the output parsed as JSON. */
    public function getJson():Promise<Dynamic> {
        return getString().then(s -> haxe.Json.parse(s));
    }

}
