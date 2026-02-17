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

    function hasSourceId(value:Source, sourceId:SourceId):Bool {
        return Lambda.exists(value.data, d -> d.id == sourceId);
    }

    function mergePartial(stone:AnyStone, existing:Source, addition:Source, markComplete:Bool):Promise<Source> {
        // Build merged data: upsert by sourceId.
        var mergedData = existing.data.copy();
        if (addition != null) {
            for (newItem in addition.data) {
                var replaced = false;
                for (i in 0...mergedData.length) {
                    if (mergedData[i].id == newItem.id) {
                        mergedData[i] = newItem;
                        replaced = true;
                        break;
                    }
                }
                if (!replaced) mergedData.push(newItem);
            }
        }
        var merged = new Source(mergedData, existing.hash, stone, existing.ctime, markComplete);
        // Replace in cache array.
        var values = cache.get(key(stone));
        var idx = values.indexOf(existing);
        if (idx >= 0) values[idx] = merged;
        return Promise.resolve(merged);
    }

    function replaceEntry(stone:AnyStone, existing:Source, replacement:Source):Promise<Source> {
        var values = cache.get(key(stone));
        var idx = values.indexOf(existing);
        if (idx >= 0) values[idx] = replacement;
        return Promise.resolve(replacement);
    }

}
