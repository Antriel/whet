package whet.route;

import whet.WhetSource.WhetSourceData;

abstract Router(Array<RoutePath>) from Array<RoutePath> {

    @:from public static inline function fromMap(m:Map<String, Route>):Router return new Router(m);

    public inline function new(routes:Map<String, Route> = null) {
        if (routes == null) this = []
        else this = [for (under => route in routes) { routeUnder: under, route: route }];
    }

    public inline function route(under:SourceId, route:Route)
        this.push({ routeUnder: under, route: route });

    /**
     * Find data sources routed under `id`. By default only single result is returned if `id` 
     * is not a directory, all results otherwise. This can be overriden by providing a second argument.
     */
    public function find(id:SourceId, firstOnly:Null<Bool> = null):Array<RouteResult> {
        if (firstOnly == null) firstOnly = !id.isDir();
        var res:Array<RouteResult> = [];
        for (path in this) {
            inline function check(item:RouteResult) {
                if (id.isDir()) { // Everything in this dir.
                    var rel = item.serveId.relativeTo(id);
                    if (rel != null) {
                        item.serveId = rel;
                        res.push(item);
                    }
                } else { // Everything with that exact name.
                    if (id == item.serveId) {
                        item.serveId = id.withExt;
                        res.push(item);
                    }
                }
            }
            var list = path.route.list();
            if (path.routeUnder.isDir()) {
                for (item in list) {
                    item.serveId = item.serveId.getPutInDir(path.routeUnder);
                    check(item);
                }
            } else {
                for (item in list) {
                    item.serveId = path.routeUnder;
                    check(item);
                }
            }
        }
        if (firstOnly && res.length > 1) res.resize(1);
        return res;
    }

}

typedef RoutePath = {

    var routeUnder:SourceId;
    var route:Route;

}
