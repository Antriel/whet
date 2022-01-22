package whet.magic;

import whet.magic.MaybeArray.makeArray;
import whet.route.Route;
import whet.stones.Files;

/**
 * Anything that can be transformed into `Route`.
 */
typedef RouteType = MaybeArray<EitherType<String, AnyStone>>;

function makeRoute(routeType:RouteType):Route {
    return new Route([for (t in makeArray(routeType)) {
        if (t is String) {
            {
                stone: new Files({ paths: [t] }),
                path: (t:SourceId)
            }
        } else if (t is AnyStone) {
            {
                stone: t,
                path: ('/':SourceId)
            }
        } else {
            throw new js.lib.Error("Unsupported type for Route.");
        }
    }]);
}
