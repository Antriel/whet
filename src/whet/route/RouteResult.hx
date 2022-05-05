package whet.route;

@:structInit class RouteResult {

    /** Id under which this item is served by `Router`. Can be different from `sourceId`. */
    @:allow(whet.route) public var serveId(default, null):SourceId;

    /** Id under which this item is provided by the stone. */
    public final sourceId:SourceId;

    /** Stone providing this item. */
    public final source:AnyStone;

    public function get():Promise<SourceData> {
        return source.getSource().then(data -> data.get(cast sourceId));
    }

}
