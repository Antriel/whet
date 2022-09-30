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
        return getResults(new Filters(makeMinimatch(pattern)), []);
    }

    function getResults(mainFilters:Filters, results:Array<RouteResult>):Promise<Array<RouteResult>> {
        return new Promise((res, rej) -> {
            var allRouteProms = [];
            for (route in routes) {
                var routeFilters = mainFilters.clone(); // Clone filters so other routes aren't affected.
                var possible = if (route.routeUnder.isDir()) routeFilters.step(route.routeUnder);
                else routeFilters.finalize(route.routeUnder);

                if (!possible) continue;
                if (route.filter != null || route.extractDirs != null) routeFilters.add(route.filter, route.extractDirs);

                var prom:Promise<Any> = if (route.source is AnyStone) {
                    final stone:AnyStone = cast route.source;
                    stone.list().then(list -> {
                        for (sourceId in list) {
                            // We are finished for this route, check the last filter if any.
                            var finalFilters = routeFilters.clone();
                            var passed = finalFilters.finalize(sourceId);
                            // This could be optimized. We don't need to do checks, unless we have a new filter.
                            // And we should be able to avoid cloning regardless, by avoiding making modifications to the Filters.
                            if (passed) {
                                var serveId = finalFilters.getServeId();
                                results.push({ source: stone, sourceId: sourceId, serveId: serveId });
                            }
                        }
                    });
                } else if (route.source is Router) {
                    (cast route.source:Router).getResults(routeFilters, results);
                } else throw new js.lib.Error("Router source must be a Stone or a Router.");
                allRouteProms.push(prom);
            }
            Promise.all(allRouteProms).then(_ -> res(results));
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
                    final p = Path.join(saveInto, r.serveId.toCwdPath('./'));
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

}

typedef Filter = {pathSoFar:Array<String>, filter:Minimatch, inProgress:Bool, remDirs:Array<Minimatch>};

abstract Filters(Array<Filter>) from Array<Filter> {

    public inline function new(filter:Minimatch) { // TODO allow null minimatch instead of "**", and just ignore the checks.
        this = [{ pathSoFar: [], filter: filter, inProgress: true, remDirs: [] }];
    }

    public inline function finalize(finalPath:SourceId):Bool {
        var parts = finalPath.split('/');
        return iterate(f -> {
            f.inProgress = false;
            processParts(parts, f);
            f.pathSoFar = f.pathSoFar.concat(parts);
            return f.filter == null || f.filter.match(Path.posix.join(...f.pathSoFar));
        });
    }

    public inline function step(dir:SourceId):Bool {
        if (dir.length == 0 || dir == './') return true;
        var parts = dir.split('/').filter(p -> p.length > 0);
        return iterate(f -> {
            processParts(parts, f);
            f.pathSoFar = f.pathSoFar.concat(parts);
            return f.filter == null || isPathPossible(f);
        });
    }

    inline function iterate(action:Filter->Bool) {
        var res = true;
        var i = this.length;
        while (--i >= 0) { // Iterate in reverse, as we modify `parts` as we go.
            var f = this[i];
            if (f.inProgress) if (!action(f)) {
                res = false;
                break;
            }
        }
        return res;
    }

    public inline function getServeId():SourceId return Path.posix.join(...this[0].pathSoFar);

    public inline function add(f:Minimatch, extractDir:Minimatch):Void {
        if (extractDir != null && this.length > 0) // Add to the current one. Applied when adding paths.
            this[this.length - 1].remDirs.push(extractDir);
        this.push({
            pathSoFar: [],
            filter: f,
            inProgress: true,
            remDirs: []
        });
    }

    public inline function clone():Filters {
        return this.map(f -> {
            filter: f.filter,
            pathSoFar: f.pathSoFar.copy(),
            inProgress: f.inProgress,
            remDirs: f.remDirs.copy()
        });
    }

    inline function processParts(parts:Array<String>, f:Filter) {
        if (f.remDirs.length == 0) return;
        var i = parts.length;
        while (--i >= 0) {
            for (r in f.remDirs) {
                if (r.match(parts[i] + '/')) {
                    parts.splice(i, 1);
                    break;
                }
            }
        }
    }

    function isPathPossible(f:Filter):Bool {
        inline function onHit(hit:Bool) {
            if (f.filter.options.flipNegate) return hit;
            return hit != f.filter.negate;
        }
        // If we are only interested in base filename, we can't determine result yet.
        if (f.filter.options.matchBase) return true;
        for (set in f.filter.set) {
            final hit = f.filter.matchOne(cast f.pathSoFar, set, true); // (`cast` needed – wrong type definitions.)
            if (hit) return onHit(true);
        }
        return onHit(false); // No hit.
    }

}

typedef RoutePath = {

    var routeUnder:SourceId;
    var source:RouterSource;
    var filter:Minimatch;
    var extractDirs:Minimatch;

}

typedef RouterSource = EitherType<AnyStone, Router>;
