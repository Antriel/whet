package whet.route;

import whet.magic.RouteType;

@:expose
class Route {

    private final routes:Array<RouteData>;

    public function new(route:RouteType) {
        this.routes = if (route is Route) (route:Route).routes.copy();
        else whet.magic.RouteType.makeRouteRoutes(route);
    }

    public function add(r:RouteType):Route {
        for (item in makeRoute(r).routes) routes.push(item);
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
                        arr.push({ source: r.stone, sourceId: path, serveId: path.relativeTo(r.path) });
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
