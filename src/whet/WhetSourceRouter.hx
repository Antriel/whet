package whet;

import whet.Whetstone;

abstract WhetSourceRouter(SourceMap) from SourceMap {

    public function find(id:SourceId):Whetstone {
        for (key => stone in this) {
            if (key == id) return stone;
            var rel = id.relativeTo(key.asDir());
            if (rel != null) {
                var foundStone = stone.findStone(rel);
                if (foundStone != null) return foundStone;
            }
        }
        return null;
    }

    public inline function add(route:SourceId, stone:Whetstone) this.set(route, stone);

}

typedef SourceMap = haxe.ds.Map<SourceId, Whetstone>;
