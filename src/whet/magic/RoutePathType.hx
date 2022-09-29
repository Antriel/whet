package whet.magic;

import whet.extern.Minimatch;
import whet.magic.MinimatchType;
import whet.route.Router;
import whet.stones.Files;

/**
 * Anything that can be transformed into `RoutePath`. Can be a Stone or Router.
 * Can also be an array of Stones, Routers, or:
 * - `[routeUnder, Stone|Router]`, where `routeUnder` is a string to serve the results under (directory or filename).
 * - `[routeUnder, Stone|Router, filter]`, where `filter` can be a glob pattern string, or a `Minimatch` object.
 * - `[routeUnder, Stone|Router, filter, extractDirs]`, where `extractDirs` can be a glob pattern,
 * or a `Minimatch` object, and is used to remove the portion of results' directory that matches.
 * Wherever Stone or Router is expected, a string can be used as a shortcut for `new Files({ paths: [<string>] })`.
 */
typedef RoutePathType = EitherType<BaseRouteType, EitherType<Array<BaseRouteType>, Array<Array<BaseRouteType>>>>;

typedef BaseRouteType = EitherType<Router, EitherType<AnyStone, EitherType<MinimatchType, String>>>;

function makeRoutePath(routerPathType:RoutePathType):Array<RoutePath> {
    inline function source(src:BaseRouteType) return if (src is String) new Files({ paths: [src] }) else src;
    if (routerPathType is Router || routerPathType is AnyStone || routerPathType is String)
        return [{ routeUnder: '', source: source(routerPathType), filter: null, extractDirs: null }];
    if (!(routerPathType is Array))
        throw new js.lib.Error("RoutePath should be a Stone, Router, or an array.");
    return [for (item in(routerPathType:Array<BaseRouteType>)) {
        if (item is Router || item is AnyStone || item is String)
            { routeUnder: '', source: source(item), filter: null, extractDirs: null };
        else if (item is Array) {
            var inner:Array<Dynamic> = cast item;
            if (!(inner[0] is String))
                throw new js.lib.Error("First element of RoutePath array should be `routeUnder` (a string).");
            if (!(inner[1] is Router || inner[1] is AnyStone || inner[1] is String))
                throw new js.lib.Error("Second element of RoutePath array should be a Stone or Router.");
            inline function mm(i:Int) {
                if (!(inner[i] is String || js.Syntax.code('{0} instanceof {1}', inner[i], Minimatch)))
                    throw new js.lib.Error((i == 2 ? "Third" : "Fourth")
                        + " element of RoutePath array should be a glob pattern (string or `minimatch` object)");
                return makeMinimatch(inner[i]);
            }
            switch inner.length {
                case 2: { routeUnder: (inner[0]:String), source: source(inner[1]), filter: null, extractDirs: null };
                case 3: { routeUnder: (inner[0]:String), source: source(inner[1]), filter: mm(2), extractDirs: null };
                case 4: { routeUnder: (inner[0]:String), source: source(inner[1]), filter: mm(2), extractDirs: mm(3) };
                case _: throw new js.lib.Error("Invalid array for a RoutePath element.");
            }
        } else {
            throw new js.lib.Error("Unexpected RoutePath element.");
        }
    }];
}
