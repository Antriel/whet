package whet.route;

import whet.WhetSource.WhetSourceData;

@:transitive abstract Router(Array<RoutePath>) {

    @:from public static inline function fromMap(m:Map<String, Route>):Router return new Router(m);

    public inline function new(routes:Map<String, Route> = null) {
        if (routes == null) this = []
        else this = [for (under => route in routes) { routeUnder: under, route: route }];
    }

    public inline function route(r:Router)
        for (path in (cast r:Array<RoutePath>)) this.push(path);

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

    /**
     * Get combined hash of all sources that would be found under supplied id.
     */
    public function getHash(id:SourceId, firstOnly:Null<Bool> = null):WhetSourceHash {
        var uniqueStones = [];
        for (item in find(id, firstOnly)) {
            if (uniqueStones.indexOf(item.source) == -1) uniqueStones.push(item.source);
        }
        return WhetSourceHash.merge(...uniqueStones.map(s -> s.getHash()));
    }

    public inline function getHashOfEverything():WhetSourceHash {
        return WhetSourceHash.merge(...this.map(path -> path.route.getHash()));
    }

    /**
     * Save files filtered by `searchId` into provided `saveInto` folder.
     */
    public function saveInto(searchId:SourceId, saveInto:String, clearFirst:Bool = true):Void {
        if (clearFirst && sys.FileSystem.exists(saveInto)) {
            Utils.deleteRecursively(saveInto);
        }
        var result = find(searchId);
        for (r in result) {
            var p = haxe.io.Path.join([saveInto, r.serveId.toRelPath('/')]);
            Utils.ensureDirExist(p);
            sys.io.File.saveBytes(p, r.get().data);
        }
    }

}

typedef RoutePath = {

    var routeUnder:SourceId;
    var route:Route;

}
