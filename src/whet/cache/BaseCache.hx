package whet.cache;

import whet.cache.Cache;

abstract class BaseCache<Key, Value:{final hash:WhetSourceHash; final ctime:Float;}> implements Cache {

    var cache:Map<Key, Array<Value>>; // Value array is ordered by use time, starting from most recently used.

    @:access(whet.Whetstone) public function get(stone:Stone, durability:CacheDurability, check:DurabilityCheck):WhetSource {
        var hash = stone.getHash();
        var generatedSource = null;
        if (hash == null) { // Default hash is hash of generated source, but generate it only once as optimization.
            generatedSource = stone.generateSource(null);
            hash = generatedSource.hash;
        }
        var values = cache.get(key(stone));
        var ageCount = val -> Lambda.count(values, v -> v != val && v.ctime > val.ctime);
        var value:Value = null;
        if (values != null && values.length > 0) {
            value = Lambda.find(values, v -> v.hash.equals(hash));
            if (value != null && check.match(SingleOnGet) && !shouldKeep(stone, value, durability, v -> 0, ageCount)) {
                remove(stone, value);
                value = null;
            }
            if (value != null) setRecentUseOrder(values, value);
        }
        var src = value != null ? source(stone, value) : null;
        if (src == null) {
            if (check.match(AllOnSet)) checkDurability(stone, values, durability, v -> values.indexOf(v) + 1, v -> ageCount(v) + 1);
            if (generatedSource == null) generatedSource = stone.generateSource(hash);
            if (generatedSource != null) src = source(stone, set(generatedSource));
        }
        if (check.match(AllOnUse | null)) checkDurability(stone, values, durability, v -> values.indexOf(v), ageCount);
        return src;
    }

    function set(source:WhetSource):Value {
        var k = key(source.origin);
        if (!cache.exists(k)) cache.set(k, []);
        var values = cache.get(k);
        var val = value(source);
        values.unshift(val);
        return val;
    }

    public function getUniqueDir(stone:Stone, baseDir:SourceId, ?hash:WhetSourceHash):SourceId {
        if (hash != null) {
            var values = cache.get(key(stone));
            if (values != null) {
                var existingVal = Lambda.find(values, v -> v.hash.equals(hash));
                if (existingVal != null) {
                    var existingPath = getDirFor(existingVal);
                    if (existingPath != null) return existingPath;
                }
            }
        }
        var filenames = getExistingDirs(stone);
        var maxNum = if (filenames != null) Lambda.fold(filenames, (fn, num) -> {
            var name = fn.dir.toRelPath();
            name.charAt(0) == 'v' ? Std.parseInt(name.substr(1)) : 0;
        }, 1);
        else 1;
        return ('v$maxNum/':SourceId).getPutInDir(baseDir);
    }

    function checkDurability(stone:Stone, values:Array<Value>, durability:CacheDurability, useIndex:Value->Int, ageIndex:Value->Int):Void {
        if (values == null || values.length == 0) return;
        var i = values.length;
        while (--i > 0) {
            if (!shouldKeep(stone, values[i], durability, useIndex, ageIndex)) remove(stone, values[i]);
        }
    }

    function shouldKeep(stone:Stone, val:Value, durability:CacheDurability, useIndex:Value->Int, ageIndex:Value->Int):Bool {
        return switch durability {
            case KeepForever: true;
            case LimitCountByLastUse(count): useIndex(val) < count;
            case LimitCountByAge(count): ageIndex(val) < count;
            case MaxAge(seconds): (Sys.time() - val.ctime) <= seconds;
            case Custom(keep): keep(source(stone, val));
            case All(keepIfAll): Lambda.foreach(keepIfAll, d -> shouldKeep(stone, val, d, useIndex, ageIndex));
            case Any(keepIfAny): Lambda.exists(keepIfAny, d -> shouldKeep(stone, val, d, useIndex, ageIndex));
        }
    }

    function setRecentUseOrder(values:Array<Value>, value:Value):Bool {
        if (values[0] == value) return false;
        values.remove(value);
        values.unshift(value);
        return true;
    }

    function remove(stone:Stone, value:Value):Void cache.get(key(stone)).remove(value);

    abstract function key(stone:Stone):Key;

    abstract function value(source:WhetSource):Value;

    abstract function source(stone:Stone, value:Value):WhetSource;

    abstract function getExistingDirs(stone:Stone):Array<SourceId>;

    abstract function getDirFor(value:Value):SourceId;

}
