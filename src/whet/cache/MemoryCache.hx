package whet.cache;

class MemoryCache extends BaseCache<Whetstone, WhetSource> {

    public function new() {
        cache = new Map();
    }

    function key(stone:Whetstone) return stone;

    function value(source:WhetSource) return source;

    function source(stone:Whetstone, value:WhetSource):WhetSource return value;

    function getExistingDirs(stone:Whetstone):Array<SourceId> {
        var list = cache.get(stone);
        if (list != null) return list.filter(s -> s.hasDir()).map(s -> s.getDirPath());
        else return null;
    }

    function getDirFor(value:WhetSource):SourceId return value.hasDir() ? value.getDirPath() : null;

}
