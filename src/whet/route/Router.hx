package whet.route;

import js.node.Path;
import whet.magic.RoutePathType;

@:expose
class Router {

    private var routes:Array<RoutePath>;

    public function new(routes:RoutePathType = null) {
        if (routes != null) this.routes = makeRoutePath(routes);
    }

    public inline function route(r:RoutePathType)
        for (path in makeRoutePath(r)) routes.push(path);

    /**
     * Find data sources routed under `id`. By default only single result is returned if `id`
     * is not a directory, all results otherwise. This can be overriden by providing a second argument.
     */
    public function find(id:String, firstOnly:Null<Bool> = null):Promise<Array<RouteResult>> {
        var sourceId:SourceId = id;
        return new Promise((res, rej) -> {
            if (firstOnly == null) firstOnly = !sourceId.isDir();
            var result:Array<RouteResult> = [];
            Promise.all([for (path in routes) {
                inline function check(item:RouteResult) {
                    if (sourceId.isDir()) { // Everything in this dir.
                        var rel = item.serveId.relativeTo(sourceId);
                        if (rel != null) {
                            item.serveId = rel;
                            result.push(item);
                        }
                    } else { // Everything with that exact name.
                        if (sourceId == item.serveId) {
                            item.serveId = sourceId.withExt;
                            result.push(item);
                        }
                    }
                }
                path.route.list().then(list -> {
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
                });
            }]).then(_ -> {
                if (firstOnly && result.length > 1) result.resize(1);
                res(result);
            });
        });
    }

    /**
     * Get combined hash of all sources that would be found under supplied id.
     */
    public function getHash(id:String, firstOnly:Null<Bool> = null):Promise<SourceHash> {
        return find(id, firstOnly).then(items -> {
            var uniqueStones = [];
            for (item in items)
                if (uniqueStones.indexOf(item.source) == -1) uniqueStones.push(item.source);
            Promise.all(uniqueStones.map(s -> s.getHash()))
                .then((hashes:Array<SourceHash>) -> SourceHash.merge(...hashes));
        });
    }

    public inline function getHashOfEverything():Promise<SourceHash> {
        return Promise.all(routes.map(path -> path.route.getHash()))
            .then((hashes:Array<SourceHash>) -> SourceHash.merge(...hashes));
    }

    /**
     * Save files filtered by `searchId` into provided `saveInto` folder.
     */
    public function saveInto(searchId:String, saveInto:String, clearFirst:Bool = true):Promise<Nothing> {
        return (if (clearFirst) Utils.deleteAll(saveInto) else Promise.resolve(null))
            .then(_ -> find(searchId)).then(result -> {
                cast Promise.all([for (r in result) {
                    final p = Path.join(saveInto, r.serveId.toRelPath('/'));
                    r.get().then(src -> Utils.saveBytes(p, src.data));
                }]);
            });
    }

    public function listContents(search:String = "/"):Promise<String> {
        return find(search).then(files -> {
            var ids = files.map(f -> f.serveId);
            ids.sort((a, b) -> a.compare(b));
            ids.join('\n');
        });
    }

}

typedef RoutePath = {

    var routeUnder:SourceId;
    var route:Route;

}
