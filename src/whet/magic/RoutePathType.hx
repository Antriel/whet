package whet.magic;

import whet.magic.RouteType;
import whet.route.Router;

/**
 * Anything that can be transformed into `Route`.
 */
typedef RoutePathType = EitherType<Router, Array<Array<BaseRouteType>>>;

@:access(whet.route.Router)
function makeRoutePath(routerPathType:RoutePathType):Array<RoutePath> {
    if (routerPathType is Router) return (routerPathType:Router).routes;
    if (!(routerPathType is Array))
        throw new js.lib.Error("RoutePath should be an array.");
    return [for (item in (routerPathType:Array<Array<BaseRouteType>>)) {
        if (!(item is Array))
            throw new js.lib.Error("RoutePath element should be an array.");
        if (item.length < 2)
            throw new js.lib.Error("RoutePath element should have at least 2 entries `[serveId, route]`.");
        if (item.length > 3)
            throw new js.lib.Error("RoutePath element should have at most 3 entries `[serveId, route, serveAs]`.");
        {
            routeUnder: ((item[0]:String):SourceId),
            route: makeRoute([item.slice(1)])
        }
    }];
}
