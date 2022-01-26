package whet.magic;

import whet.magic.MaybeArray.makeArray;
import whet.route.Route;
import whet.stones.Files;

/**
 * Anything that can be transformed into `Route`.
 */
typedef RouteType = MaybeArray<MaybeArray<BaseRouteType>>;

typedef BaseRouteType = EitherType<String, AnyStone>;

function makeRoute(routeType:RouteType):Route {
    return new Route([for (tarr in makeArray(routeType)) {
        var tinner = makeArray(tarr);
        if (tinner.length == 1) {
            getRoute(tinner[0]);
        } else if (tinner.length == 2) {
            if (!(tinner[1] is String))
                throw new js.lib.Error("Array-defined route's second element should be path (a string).");
            getRoute(tinner[0], (tinner[1]:String));
        }
    }]);
}

private function getRoute(t:BaseRouteType, ?path:SourceId) {
    return if (t is String) {
        {
            stone: new Files({ paths: [t] }),
            path: if (path != null) path else (t:SourceId)
        }
    } else if (t is AnyStone) {
        {
            stone: t,
            path: if (path != null) path else ('/':SourceId)
        }
    } else {
        throw new js.lib.Error("Unsupported type for Route.");
    }
}

// public inline static function fromResult(r:RouteResult):Route return fromResults([r]);
// public inline static function fromResults(r:Array<RouteResult>):Route
//     return new Route([for (res in r) {
//         stone: res.source,
//         path: res.sourceId
//     }]);
// public inline static function fromResults2(r:Array<Array<RouteResult>>):Route
//     return fromResults(Lambda.flatten(r));
