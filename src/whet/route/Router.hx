package whet.route;

import haxe.extern.EitherType;
import js.node.Path;
import whet.extern.Minimatch;
import whet.magic.MinimatchType;
import whet.magic.RoutePathType;

@:expose
class Router {

    private var routes:Array<RoutePath>;

    public function new(routes:RoutePathType = null) {
        this.routes = if (routes != null) makeRoutePath(routes) else [];
    }

    public inline function route(r:RoutePathType)
        for (path in makeRoutePath(r)) routes.push(path);

    /**
     * Find data sources routed under `pattern`.
     * @param pattern A glob pattern to search for.
     */
    public function get(pattern:MinimatchType = '**'):Promise<Array<RouteResult>> {
        var filter = makeMinimatch(pattern);
        return new Promise((res, rej) -> {
            var result:Array<RouteResult> = [];
            Promise.all([for (route in routes) {
                allFromRoute(route).then(list -> {
                    var routeUnderIsDir = route.routeUnder.isDir();
                    for (item in list) {
                        item.serveId = if (routeUnderIsDir) item.serveId.getPutInDir(route.routeUnder);
                        else route.routeUnder;
                        if (filter.match(cast item.serveId)) result.push(item);
                    }
                });
            }]).then(_ -> res(result));
        });
    }

    /**
     * Get combined hash of all sources that fit the `pattern`.
     */
    public function getHash(pattern:MinimatchType = '**'):Promise<SourceHash> {
        return get(pattern).then(items -> {
            var uniqueStones = [];
            for (item in items)
                if (uniqueStones.indexOf(item.source) == -1) uniqueStones.push(item.source);
            Promise.all(uniqueStones.map(s -> s.getHash()))
                .then((hashes:Array<SourceHash>) -> SourceHash.merge(...hashes));
        });
    }

    /**
     * Save files filtered by `pattern` into provided `saveInto` folder.
     */
    public function saveInto(pattern:MinimatchType, saveInto:String, clearFirst:Bool = true):Promise<Nothing> {
        return (if (clearFirst) Utils.deleteAll(saveInto) else Promise.resolve(null))
            .then(_ -> get(pattern)).then(result -> {
                cast Promise.all([for (r in result) {
                    final p = Path.join(saveInto, r.serveId.toCwdPath('/'));
                    r.get().then(src -> Utils.saveBytes(p, src.data));
                }]);
            });
    }

    public function listContents(pattern:MinimatchType = '**'):Promise<String> {
        return get(pattern).then(files -> {
            var ids = files.map(f -> f.serveId);
            ids.sort((a, b) -> a.compare(b));
            ids.join('\n');
        });
    }

    inline function allFromRoute(route:RoutePath):Promise<Array<RouteResult>> {
        if (route.source is AnyStone) {
            final stone:AnyStone = cast route.source;
            return stone.list().then(list -> {
                var arr:Array<RouteResult> = [];
                for (path in list) {
                    var serveId = getServeId(path, route);
                    if (serveId != null)
                        arr.push({ source: stone, sourceId: path, serveId: serveId });
                }
                return arr;
            });
        } else if (route.source is Router) {
            final router:Router = cast route.source;
            return router.get().then(list -> {
                var arr:Array<RouteResult> = [];
                for (result in list) {
                    var serveId = getServeId(result.serveId, route);
                    if (serveId != null) {
                        result.serveId = serveId;
                        arr.push(result);
                    }
                }
                return arr;
            });
        } else throw new js.lib.Error("Router source must be a Stone or a Router.");
    }

    inline function getServeId(path:SourceId, route:RoutePath) {
        var serveId = null;
        if (route.filter == null || route.filter.match(cast path)) {
            serveId = path;
            if (route.extractDirs != null) {
                var dir:String = cast path;
                do {
                    dir = dir.substring(0, dir.lastIndexOf('/'));
                    if (route.extractDirs.match(dir + '/')) {
                        serveId = path.relativeTo(dir + '/');
                        break;
                    }
                } while (dir.length > 0);
            }
        }
        return serveId;
    }

}

typedef RoutePath = {

    var routeUnder:SourceId;
    var source:RouterSource;
    var filter:Minimatch;
    var extractDirs:Minimatch;

}

typedef RouterSource = EitherType<AnyStone, Router>;
