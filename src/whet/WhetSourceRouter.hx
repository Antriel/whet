package whet;

import whet.Whetstone;

abstract WhetSourceRouter(SourceMap) from SourceMap {

    public function find(id:SourceId):WhetSource {
        for (key => stone in this) {
            if (key == id) return stone.getSource();
            var rel = id.relativeTo(key.dir);
            if (rel != null) {
                var source = stone.findSource(rel);
                if (source != null) return source;
            }
        }
        return null;
    }

    public inline function add(route:SourceId, stone:Whetstone) this.set(route, stone);

}

typedef SourceMap = haxe.ds.Map<SourceId, Whetstone>;
