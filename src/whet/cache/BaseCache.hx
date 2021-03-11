package whet.cache;

class BaseCache<Key, Value:{final hash:WhetSourceHash; final ctime:Float;}> implements Cache {

    var cache:Map<Key, Array<Value>>; // Value array is ordered by use time, starting from most recently used.

    @:access(whet.Whetstone) public function get(stone:Whetstone, durability:CacheDurability, check:DurabilityCheck):WhetSource {
        // So, what do we need here, and what do we return?
        // We probably need the stone to have `key(stone)` working, but do we generate the full source or just the structure?
        // Do we add `hash` param here? Probably yeah.
        // So, step 1: Change how we generate and store stuff in all caches, from single bytes to handling the structure.
        // Step 2: Loading _from_ the cache generates the same structure.
        // Step 3: Win.
        var values = cache.get(key(stone));
        var ageCount = val -> Lambda.count(values, v -> v != val && v.ctime > val.ctime);
        var value:Value = null;
        if (values != null && values.length > 0) {
            var hash = stone.getHash(); // Null hash means use default -> byte hash of the generated result.
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
            var newData = stone.generateData();
            if (newData != null) src = source(stone, set(stone, newData));
        }
        if (check.match(AllOnUse | null)) checkDurability(stone, values, durability, v -> values.indexOf(v), ageCount);
        return src;
    }

    function set(stone:Whetstone, source:WhetSource):Value {
        var k = key(stone);
        if (!cache.exists(k)) cache.set(k, []);
        var values = cache.get(k);
        var val = value(stone, source);
        values.unshift(val);
        return val;
    }

    public function getUniqueName(stone:Whetstone, id:SourceId, ?hash:WhetSourceHash):SourceId {
        if (hash != null) {
            var values = cache.get(key(stone));
            if (values != null) {
                var existingVal = Lambda.find(values, v -> v.hash.equals(hash));
                if (existingVal != null) {
                    var existingPath = getPathFor(existingVal);
                    if (existingPath != null) return existingPath;
                }
            }
        }
        var filenames = getFilenames(stone);
        if (filenames != null) {
            return Utils.makeUnique(id, id -> filenames.indexOf(id) >= 0, (id, v) -> {
                id.withoutExt += v;
                id;
            });
        } else return id;
    }

    function checkDurability(stone:Whetstone, values:Array<Value>, durability:CacheDurability, useIndex:Value->Int,
            ageIndex:Value->Int):Void {
        if (values == null || values.length == 0) return;
        var i = values.length;
        while (--i > 0) {
            if (!shouldKeep(stone, values[i], durability, useIndex, ageIndex)) remove(stone, values[i]);
        }
    }

    function shouldKeep(stone:Whetstone, val:Value, durability:CacheDurability, useIndex:Value->Int, ageIndex:Value->Int):Bool {
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

    function remove(stone:Whetstone, value:Value):Void cache.get(key(stone)).remove(value);

    function key(stone:Whetstone):Key return null;

    function value(stone:Whetstone, source:WhetSource):Value return null;

    function source(stone:Whetstone, value:Value):WhetSource return null;

    function getFilenames(stone:Whetstone):Array<SourceId> return null;

    function getPathFor(value:Value):SourceId return null;

}
