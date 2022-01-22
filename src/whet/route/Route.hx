package whet.route;

class Route {

    private final routes:Array<RouteData>;

    public function new(routes:Array<RouteData>) {
        this.routes = routes;
    }

    public inline static function fromStone(stone:AnyStone):Route return fromStoneArray([stone]);

    public inline static function fromStoneArray(stones:Array<AnyStone>):Route
        return new Route([for (stone in stones) {
            stone: stone,
            path: ('/':SourceId)
        }]);

    // TODO handle the Maps/RouteResults.
    // public inline static function fromSourceIdMap<T:AnyStone>(m:Map<T, SourceId>):Route
    //     return new Route([for (stone => path in m) {
    //         stone: stone,
    //         path: path
    //     }]);
    // public inline static function fromMap<T:AnyStone>(m:Map<T, String>):Route
    //     return new Route([for (stone => path in m) {
    //         stone: stone,
    //         path: (path:SourceId)
    //     }]);
    // public inline static function fromResult(r:RouteResult):Route return fromResults([r]);
    // public inline static function fromResults(r:Array<RouteResult>):Route
    //     return new Route([for (res in r) {
    //         stone: res.source,
    //         path: res.sourceId
    //     }]);
    // public inline static function fromResults2(r:Array<Array<RouteResult>>):Route
    //     return fromResults(Lambda.flatten(r));

    public function add(r:Route):Route {
        // for (item in (cast r:Array<RouteData>)) routes.push(item);
        // TODO no casting anymore.
        return this;
    }

    public inline function getHash():Promise<SourceHash> {
        return Promise.all(routes.map(r -> r.stone.getHash()))
            .then((hashes:Array<SourceHash>) -> SourceHash.merge(...hashes));
    }

    public function list():Promise<Array<RouteResult>> {
        // Merge sequentially to keep ordering deterministic.
        return Promise.all([
            for (r in routes) {
                r.stone.list().then(list -> {
                    var arr:Array<RouteResult> = [];
                    if (r.path.isDir()) for (path in list) {
                        // TODO: we used `serveId: path.relativeTo(r.path)` before. Was that correct? Make tests.
                        arr.push({ source: r.stone, sourceId: path, serveId: path });
                    } else for (path in list) if (path == r.path)
                        arr.push({ source: r.stone, sourceId: path, serveId: (path.withExt:SourceId) });
                    return arr;
                });
            }]
        ).then(data -> Lambda.flatten(data));
    }

    public function getData():Promise<Array<SourceData>> {
        return cast list().then(l -> Promise.all(l.map(r -> r.get())));
    }

}

typedef RouteData = {

    var stone:AnyStone;
    var path:SourceId;

};
