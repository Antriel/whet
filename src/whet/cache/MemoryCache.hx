package whet.cache;

class MemoryCache extends BaseCache<Whetstone, WhetSource> {

    public function new() {
        cache = new Map();
    }

    override function key(stone:Whetstone) return stone;

    override function value(stone:Whetstone, source:WhetSource) return source;

    override function source(stone:Whetstone, value:WhetSource):WhetSource return value;

    override function getFilenames(stone:Whetstone):Array<SourceId> {
        var list = cache.get(stone);
        if (list != null) return list.filter(s -> s.hasFile()).map(s -> s.getFilePath());
        else return null;
    }

    override function getPathFor(value:WhetSource):SourceId return value.hasFile() ? value.getFilePath() : null;

}
