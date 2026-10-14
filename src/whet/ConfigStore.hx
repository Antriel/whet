package whet;

import haxe.DynamicAccess;
import js.lib.WeakMap;

@:expose
class ConfigStore {

    public final path:String;

    var data:Null<DynamicAccess<Dynamic>> = null;
    var persistedData:Null<DynamicAccess<Dynamic>> = null;
    final file:TrackedFile;
    var loadPromise:Null<Promise<Nothing>> = null;
    /** Stones whose unsaved entry was also changed on disk (by someone else) since it was last read. */
    final conflicts = new js.lib.Set<String>();

    final baselines = new WeakMap<DynamicAccess<Dynamic>>();
    final appliedPatches = new WeakMap<DynamicAccess<Dynamic>>();

    public function new(path:String) {
        this.path = path;
        file = new TrackedFile(path);
    }

    public function ensureApplied(stone:AnyStone):Promise<Nothing> {
        return reload().then(_ -> {
            if (!baselines.has(stone))
                captureBaseline(stone);
            var entry = getEntry(stone);
            var lastApplied = appliedPatches.get(stone);
            if (entry == lastApplied) return null;
            if (entry != null && lastApplied != null
                && haxe.Json.stringify(entry) == haxe.Json.stringify(lastApplied))
                return null;
            applyPatch(stone);
            return null;
        });
    }

    public function setPatch(stone:AnyStone, patch:Dynamic):Promise<Nothing> {
        return reload().then(_ -> {
            if (data == null) data = new DynamicAccess();
            data.set(stone.id, patch);
            conflicts.delete(stone.id); // An explicit patch replaces the entry, whatever is on disk.
            return persist(false);
        }).then(_ -> {
            applyPatch(stone);
            return null;
        });
    }

    public function getEntryById(stoneId:String):Dynamic {
        if (data == null) return null;
        return data.get(stoneId);
    }

    public function setEntry(stoneId:String, patch:Dynamic):Void {
        if (data == null) data = new DynamicAccess();
        data.set(stoneId, patch);
    }

    public function clearEntry(stoneId:String):Void {
        if (data == null) return;
        if (persistedData != null && persistedData.exists(stoneId)) {
            data.set(stoneId, deepClone(persistedData.get(stoneId)));
        } else {
            data.remove(stoneId);
        }
        conflicts.delete(stoneId);
    }

    /**
     * Persist the current data. External edits are merged in first, per entry (see `doReload`).
     * Rejects with a `TrackedFile.CONFLICT` error, with `stoneIds`, if an unsaved entry was also
     * changed on disk, unless `force` — which keeps the in-memory version of those entries; other
     * entries' external edits survive either way.
     */
    public function flush(force:Bool = false):Promise<Nothing> {
        return reload().then(_ -> persist(force));
    }

    public function isDirty(?stoneId:String):Bool {
        if (stoneId != null) {
            var current = if (data != null) data.get(stoneId) else null;
            var persisted = if (persistedData != null) persistedData.get(stoneId) else null;
            return !sameJson(current, persisted);
        }
        // Global dirty check.
        var currentStr = if (data != null) haxe.Json.stringify(data) else "{}";
        var persistedStr = if (persistedData != null) haxe.Json.stringify(persistedData) else "{}";
        return currentStr != persistedStr;
    }

    function reload():Promise<Nothing> {
        if (loadPromise != null) return loadPromise;
        loadPromise = doReload().then(result -> {
            loadPromise = null;
            return result;
        }).catchError(e -> {
            loadPromise = null;
            return Promise.reject(e);
        });
        return loadPromise;
    }

    function doReload():Promise<Nothing> {
        return file.changed().then(changed -> {
            if (!changed && data != null) return Promise.resolve(null);
            return file.read().then(content -> {
                // File doesn't exist (yet) → empty.
                merge(content != null ? haxe.Json.parse(content) : new DynamicAccess());
                return null;
            }).catchError(e -> {
                file.forget(); // Unparseable: retry on the next access instead of keeping stale data.
                return Promise.reject(e);
            });
        });
    }

    /**
     * Merge a fresh disk version in, per entry: clean entries take the disk version, unsaved
     * (preview) entries are kept. An unsaved entry whose disk version also changed — to something
     * other than the unsaved value — is recorded as a conflict for `flush` to report.
     */
    function merge(disk:DynamicAccess<Dynamic>):Void {
        if (data == null) {
            data = disk;
            persistedData = deepClone(disk);
            return;
        }
        var merged = new DynamicAccess<Dynamic>();
        var keys = [for (k in disk.keys()) k];
        for (k in data.keys()) if (!disk.exists(k)) keys.push(k);
        if (persistedData != null) for (k in persistedData.keys()) if (keys.indexOf(k) == -1) keys.push(k);
        for (k in keys) {
            if (!isDirty(k)) {
                if (disk.exists(k)) merged.set(k, deepClone(disk.get(k)));
                continue;
            }
            if (data.exists(k)) merged.set(k, data.get(k));
            var base = persistedData != null ? persistedData.get(k) : null;
            if (!sameJson(base, disk.get(k)) && !sameJson(data.get(k), disk.get(k))) conflicts.add(k);
        }
        data = merged;
        persistedData = deepClone(disk);
    }

    /** Write the current data, unless an unsaved entry conflicts with the disk and not `force`. */
    function persist(force:Bool):Promise<Nothing> {
        var conflicting = [for (k in conflicts) if (isDirty(k)) k];
        if (conflicting.length > 0 && !force) {
            var err = TrackedFile.conflictError(path, 'Config entries changed both here and on disk: ${conflicting.join(', ')}.');
            (cast err).stoneIds = conflicting;
            return Promise.reject(err);
        }
        if (data == null) data = new DynamicAccess();
        var json = haxe.Json.stringify(data, null, '  ');
        return file.write(json, force).then(_ -> {
            // What was written, not `data` now: entries edited during the write are still unsaved.
            persistedData = haxe.Json.parse(json);
            conflicts.clear();
            return null;
        });
    }

    static function sameJson(a:Dynamic, b:Dynamic):Bool {
        if (a == b) return true;
        if (a == null || b == null) return false;
        return haxe.Json.stringify(a) == haxe.Json.stringify(b);
    }

    function getEntry(stone:AnyStone):Null<DynamicAccess<Dynamic>> {
        if (data == null) return null;
        return data.get(stone.id);
    }

    public static final BASE_CONFIG_KEYS = ['cacheStrategy', 'id', 'project', 'dependencies', 'configStore'];

    function captureBaseline(stone:AnyStone):Void {
        var baseline = new DynamicAccess<Dynamic>();
        var configObj:DynamicAccess<Dynamic> = cast stone.config;
        for (key => val in configObj) {
            if (BASE_CONFIG_KEYS.contains(key)) continue;
            if (isJsonSerializable(val))
                baseline.set(key, deepClone(val));
        }
        baselines.set(stone, baseline);
    }

    function applyPatch(stone:AnyStone):Void {
        var baseline = baselines.get(stone);
        if (baseline == null) return;
        var entry = getEntry(stone);
        var configObj:DynamicAccess<Dynamic> = cast stone.config;

        // Restore baseline first, then merge patch.
        for (key => baseVal in baseline) {
            if (entry != null && entry.exists(key)) {
                configObj.set(key, deepMerge(deepClone(baseVal), entry.get(key)));
            } else {
                configObj.set(key, deepClone(baseVal));
            }
        }

        // Apply patch keys that don't exist in baseline (new keys introduced by patch).
        if (entry != null) {
            for (key => val in entry) {
                if (!baseline.exists(key)) {
                    configObj.set(key, deepClone(val));
                }
            }
        }

        // Remove keys that were added by a previous patch but not in new patch and not in baseline.
        var prevApplied = appliedPatches.get(stone);
        if (prevApplied != null) {
            for (key => _ in prevApplied) {
                if (!baseline.exists(key) && (entry == null || !entry.exists(key))) {
                    configObj.remove(key);
                }
            }
        }

        // Store a deep clone of the applied entry for change detection.
        appliedPatches.set(stone, if (entry != null) deepClone(entry) else null);
    }

    public static function isJsonSerializable(val:Dynamic):Bool {
        if (val == null) return true;
        if (js.Syntax.code('typeof {0} === "function"', val)) return false;
        if (js.Syntax.code('typeof {0} !== "object"', val)) return true; // primitives
        if (val is Array) return true;
        // Only plain objects are serializable. Any class instance (Stone, Router,
        // server plugins, Node Timers, Map/Set/Date, ...) is not – deepClone would
        // otherwise traverse its cyclic internals and could overflow the stack.
        return js.Syntax.code(
            '(Object.getPrototypeOf({0}) === null || Object.getPrototypeOf({0}) === Object.prototype)', val);
    }

    public static function deepClone(val:Dynamic):Dynamic {
        if (val == null) return null;
        if (!isJsonSerializable(val)) return null;
        if (val is Array) {
            var arr:Array<Dynamic> = val;
            return arr.map(item -> deepClone(item));
        }
        if (js.Syntax.code('typeof {0} === "object"', val)) {
            var obj:DynamicAccess<Dynamic> = val;
            var result = new DynamicAccess<Dynamic>();
            for (key => v in obj)
                result.set(key, deepClone(v));
            return result;
        }
        return val;
    }

    @:keep public static function deepMerge(base:Dynamic, patch:Dynamic):Dynamic {
        if (patch == null) return null;
        if (base == null) return deepClone(patch);
        if (patch is Array) return deepClone(patch);
        if (js.Syntax.code('typeof {0} === "object"', patch)
            && js.Syntax.code('typeof {0} === "object"', base) && !(base is Array)) {
            var baseObj:DynamicAccess<Dynamic> = base;
            var patchObj:DynamicAccess<Dynamic> = patch;
            var result = new DynamicAccess<Dynamic>();
            for (key => v in baseObj)
                result.set(key, v);
            for (key => v in patchObj)
                result.set(key, deepMerge(result.get(key), v));
            return result;
        }
        return deepClone(patch);
    }

}
