package whet.route;

import whet.WhetSource.WhetSourceData;

@:transitive abstract Route(Array<RouteData>) { // Cannot have implicit `from` cast, see https://github.com/HaxeFoundation/haxe/issues/10187.

    @:from public inline static function fromStone(stone:Stone):Route return fromStoneArray([stone]);

    @:from public inline static function fromStoneArray(stones:Array<Stone>):Route
        return cast [for (stone in stones) {
            stone: stone,
            path: ('/':SourceId)
        }];

    @:from public inline static function fromSourceIdMap<T:Stone>(m:Map<T, SourceId>):Route
        return cast [for (stone => path in m) {
            stone: stone,
            path: path
        }];

    @:from public inline static function fromMap<T:Stone>(m:Map<T, String>):Route
        return cast [for (stone => path in m) {
            stone: stone,
            path: (path:SourceId)
        }];

    @:from public inline static function fromResult(r:RouteResult):Route return fromResults([r]);

    @:from public inline static function fromResults(r:Array<RouteResult>):Route
        return cast [for (res in r) {
            stone: res.source,
            path: res.sourceId
        }];

    @:from public inline static function fromResults2(r:Array<Array<RouteResult>>):Route
        return fromResults(Lambda.flatten(r));

    public function add(r:Route):Route {
        for (item in (cast r:Array<RouteData>)) this.push(item);
        return cast this;
    }

    public inline function getHash():WhetSourceHash {
        return WhetSourceHash.merge(...this.map(r -> r.stone.getHash()));
    }

    public function list():Array<RouteResult> {
        var res:Array<RouteResult> = [];
        for (r in this) {
            var list = r.stone.list();
            if (r.path.isDir()) for (path in list) {
                var rel = path.relativeTo(r.path);
                if (rel != null)
                    res.push({ source: r.stone, sourceId: path, serveId: rel });
            } else for (path in list) if (path == r.path)
                res.push({ source: r.stone, sourceId: path, serveId: path.withExt });
        }
        return res;
    }

    public function getData():Array<WhetSourceData> {
        return list().map(r -> r.get());
    }

}

typedef RouteData = {

    var stone:Stone;
    var path:SourceId;

};
