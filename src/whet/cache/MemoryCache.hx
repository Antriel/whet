package whet.cache;

class MemoryCache extends BaseCache<AnyStone, Source> {

    public function new(rootDir) {
        super(rootDir, new Map());
    }

    function key(stone:AnyStone) return stone;

    function value(source:Source) return Promise.resolve(source);

    function source(stone:AnyStone, value:Source):Promise<Source> return Promise.resolve(value);

    function getExistingDirs(stone:AnyStone):Array<SourceId> {
        var list = cache.get(stone);
        if (list != null) return list.map(s -> s.tryDirPath()).filter(p -> p != null);
        else return null;
    }

    function getDirFor(value:Source):SourceId return value.tryDirPath();

}
