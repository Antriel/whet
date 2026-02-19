package whet;

import haxe.DynamicAccess;
import js.lib.WeakMap;
import js.node.Fs;
import js.node.Path;
import whet.route.Router;

@:expose
class ConfigStore {

    public final path:String;

    var data:Null<DynamicAccess<Dynamic>> = null;
    var persistedData:Null<DynamicAccess<Dynamic>> = null;
    var mtimeMs:Null<Float> = null;
    var size:Null<Float> = null;
    var loadPromise:Null<Promise<Nothing>> = null;

    final baselines = new WeakMap<DynamicAccess<Dynamic>>();
    final appliedPatches = new WeakMap<DynamicAccess<Dynamic>>();

    public function new(path:String) {
        this.path = path;
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
            return writeFile();
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
    }

    public function flush():Promise<Nothing> {
        return writeFile();
    }

    public function isDirty(?stoneId:String):Bool {
        if (stoneId != null) {
            var current = if (data != null) data.get(stoneId) else null;
            var persisted = if (persistedData != null) persistedData.get(stoneId) else null;
            if (current == persisted) return false;
            if (current == null || persisted == null) return true;
            return haxe.Json.stringify(current) != haxe.Json.stringify(persisted);
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
        return statFile().then(stats -> {
            if (stats == null) {
                // File doesn't exist (yet).
                if (data == null) {
                    data = new DynamicAccess();
                    persistedData = new DynamicAccess();
                }
                return Promise.resolve(null);
            }
            var newMtime:Float = (cast stats).mtimeMs;
            var newSize:Float = (cast stats).size;
            if (newMtime == mtimeMs && newSize == size) {
                return Promise.resolve(null);
            }
            return readAndParse().then(_ -> {
                mtimeMs = newMtime;
                size = newSize;
                return null;
            });
        });
    }

    function statFile():Promise<Dynamic> {
        return new Promise((res, rej) -> Fs.stat(path, (err, stats) -> {
            if (err != null) {
                var code:String = js.Syntax.code('{0}.code', err);
                if (code == 'ENOENT') res(null)
                else rej(err);
            } else res(stats);
        }));
    }

    function readAndParse():Promise<Nothing> {
        return new Promise((res, rej) -> Fs.readFile(path, { encoding: 'utf-8' }, (err, content) -> {
            if (err != null) rej(err)
            else {
                data = haxe.Json.parse(content);
                persistedData = deepClone(data);
                res(null);
            }
        }));
    }

    function writeFile():Promise<Nothing> {
        return Utils.ensureDirExist(Path.dirname(path)).then(_ -> {
            var content = haxe.Json.stringify(data, null, '  ');
            return new Promise((res, rej) -> Fs.writeFile(path, content, err -> {
                if (err != null) rej(err)
                else Fs.stat(path, (err, stats) -> {
                    if (err != null) rej(err)
                    else {
                        mtimeMs = (cast stats).mtimeMs;
                        size = (cast stats).size;
                        persistedData = deepClone(data);
                        res(null);
                    }
                });
            }));
        });
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
        if (val is Stone) return false;
        if (val is Router) return false;
        if (js.Syntax.code('typeof {0} === "function"', val)) return false;
        return true;
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
