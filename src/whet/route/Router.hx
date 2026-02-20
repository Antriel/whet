package whet.route;

import haxe.extern.EitherType;
import js.node.Path;
import minimatch.Minimatch;
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
    public function get(pattern:MinimatchType = null):Promise<Array<RouteResult>> {
        return getResults(new Filters(pattern != null ? makeMinimatch(pattern) : null), []);
    }

    function getResults(mainFilters:Filters, results:Array<RouteResult>):Promise<Array<RouteResult>> {
        return new Promise((res, rej) -> {
            var allRouteProms = [];
            var queryIsPattern = mainFilters.isWildcardQuery();

            for (route in routes) {
                var routeFilters = mainFilters.clone(); // Clone filters so other routes aren't affected.
                var possible = if (route.routeUnder.isDir()) routeFilters.step(route.routeUnder);
                else routeFilters.finalize(route.routeUnder);

                if (!possible) continue;
                if (route.filter != null || route.extractDirs != null) routeFilters.add(route.filter, route.extractDirs);

                // Output filter check - skip sources that can't possibly match the query
                var outputFilter:Null<OutputFilter> = null;
                if (route.source is AnyStone) {
                    outputFilter = (cast route.source:AnyStone).getOutputFilter();
                } else if (route.source is Router) {
                    outputFilter = (cast route.source:Router).getOutputFilter();
                }

                if (outputFilter != null) {
                    var queryPattern = routeFilters.getQueryPattern();
                    if (queryPattern != null &&
                        !OutputFilterMatcher.couldMatch(queryPattern, outputFilter, queryIsPattern)) {
                        continue;  // Skip this source entirely
                    }
                }

                var prom:Promise<Any> = if (route.source is AnyStone) {
                    final stone:AnyStone = cast route.source;
                    stone.listIds().then(list -> {
                        for (sourceId in list) {
                            var serveId = routeFilters.tryFinalize(sourceId);
                            if (serveId != null) {
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
     * Includes matched serveIds in hash to capture filter effects.
     */
    public function getHash(pattern:MinimatchType = null):Promise<SourceHash> {
        return get(pattern).then(items -> {
            var uniqueStones = [];
            var serveIds = [];
            for (item in items) {
                if (uniqueStones.indexOf(item.source) == -1) uniqueStones.push(item.source);
                serveIds.push(item.serveId);
            }
            serveIds.sort((a, b) -> a.compare(b)); // Consistent ordering
            Promise.all(uniqueStones.map(s -> s.getHash()))
                .then((hashes:Array<SourceHash>) -> {
                    // Sort hashes for consistent ordering (stone order in results is non-deterministic)
                    hashes.sort((a, b) -> a.toString() < b.toString() ? -1 : a.toString() > b.toString() ? 1 : 0);
                    // Include serveIds in hash to capture filter effects
                    return SourceHash.merge(...hashes).add(SourceHash.fromString(serveIds.join('\n')));
                });
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

    /** Get the raw Buffer of the first matching result. */
    public function getData(pattern:MinimatchType = null):Promise<js.node.Buffer> {
        return get(pattern).then(r -> r[0].getData());
    }

    /** Get the first matching result as a UTF-8 string. */
    public function getString(pattern:MinimatchType = null):Promise<String> {
        return get(pattern).then(r -> r[0].getString());
    }

    /** Get the first matching result parsed as JSON. */
    public function getJson(pattern:MinimatchType = null):Promise<Dynamic> {
        return get(pattern).then(r -> r[0].getJson());
    }

    public function listContents(pattern:MinimatchType = null):Promise<String> {
        return get(pattern).then(files -> {
            var ids = files.map(f -> f.serveId);
            ids.sort((a, b) -> a.compare(b));
            ids.join('\n');
        });
    }

    /**
     * Compute combined output filter from all routes.
     * Must be dynamic (not cached) because Stone configs can change externally.
     */
    public function getOutputFilter():Null<OutputFilter> {
        var allExtensions = new Array<String>();
        var allPatterns = new Array<String>();
        var hasUnfiltered = false;

        for (route in routes) {
            var childFilter:Null<OutputFilter> = null;

            if (route.source is AnyStone) {
                childFilter = (cast route.source:AnyStone).getOutputFilter();
            } else if (route.source is Router) {
                childFilter = (cast route.source:Router).getOutputFilter();
            }

            if (childFilter == null) {
                hasUnfiltered = true;
                break;  // Can't filter if any child is unfiltered
            }

            if (childFilter.extensions != null)
                for (ext in childFilter.extensions)
                    if (allExtensions.indexOf(ext) == -1) allExtensions.push(ext);

            if (childFilter.patterns != null)
                for (p in childFilter.patterns) {
                    // Prepend route prefix to pattern
                    var prefixed = Path.posix.join(route.routeUnder, p);
                    allPatterns.push(prefixed);
                }
        }

        if (hasUnfiltered) return null;
        return {
            extensions: allExtensions.length > 0 ? allExtensions : null,
            patterns: allPatterns.length > 0 ? allPatterns : null
        };
    }

}

typedef Filter = {

    pathSoFar:haxe.ds.ReadOnlyArray<String>,
    filter:Minimatch,
    inProgress:Bool,
    remDirs:haxe.ds.ReadOnlyArray<Minimatch>

};

abstract Filters(Array<Filter>) from Array<Filter> {

    public inline function new(filter:Minimatch) {
        this = [{ pathSoFar: [], filter: filter, inProgress: true, remDirs: [] }];
    }

    public inline function finalize(finalPath:SourceId):Bool {
        var parts = finalPath.split('/');
        return iterate(f -> {
            f.inProgress = false;
            processParts(parts, f);
            f.pathSoFar = f.pathSoFar.concat(parts);
            return f.filter == null || f.filter.match(Path.posix.join(...(cast f.pathSoFar:Array<String>)));
        });
    }

    /** Like finalize, but restores filter state afterwards. Returns serveId on match, null otherwise. */
    public function tryFinalize(finalPath:SourceId):Null<SourceId> {
        // Fast path for single filter (common case) — zero extra allocations.
        if (this.length == 1) {
            var f = this[0];
            var savedPath = f.pathSoFar;
            var savedIP = f.inProgress;
            var passed = finalize(finalPath);
            var serveId = if (passed) getServeId() else null;
            f.pathSoFar = savedPath;
            f.inProgress = savedIP;
            return serveId;
        }
        // General case: save state per filter. Refs are stable since pathSoFar/remDirs are
        // effectively immutable (always replaced via concat, never mutated in-place).
        var arr:Array<Dynamic> = cast this;
        var saved = [for (f in arr) { p: f.pathSoFar, ip: f.inProgress }];
        var passed = finalize(finalPath);
        var serveId = if (passed) getServeId() else null;
        var i = 0;
        for (f in arr) {
            f.pathSoFar = saved[i].p;
            f.inProgress = saved[i].ip;
            i++;
        }
        return serveId;
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

    public inline function getServeId():SourceId
        return Path.posix.join(...(cast this[0].pathSoFar:Array<String>));

    public inline function add(f:Minimatch, extractDir:Minimatch):Void {
        if (extractDir != null && this.length > 0) // Add to the current one. Applied when adding paths.
            this[this.length - 1].remDirs = this[this.length - 1].remDirs.concat([extractDir]);
        this.push({
            pathSoFar: [],
            filter: f,
            inProgress: true,
            remDirs: []
        });
    }

    public inline function clone():Filters {
        // pathSoFar and remDirs are effectively immutable (always replaced via concat, never mutated
        // in-place), so sharing references is safe — the next write creates a new array.
        return this.map(f -> {
            filter: f.filter,
            pathSoFar: f.pathSoFar,
            inProgress: f.inProgress,
            remDirs: f.remDirs
        });
    }

    /**
     * Get the original query pattern string, or null if no filter.
     */
    public inline function getQueryPattern():Null<String> {
        return if (this.length > 0 && this[0].filter != null) this[0].filter.pattern else null;
    }

    /**
     * Check if the query is a wildcard pattern (contains * or ?).
     */
    public inline function isWildcardQuery():Bool {
        var pattern = getQueryPattern();
        return pattern != null && (pattern.indexOf('*') != -1 || pattern.indexOf('?') != -1);
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
