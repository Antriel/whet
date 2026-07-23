package whet.stones;

import haxe.DynamicAccess;
import whet.Stone.AnyStone;
import whet.route.Router;

/**
 * Turns JSON stone configs into live configs by resolving reference sentinels:
 * - `{"$stone": "<id>"}` → the live stone from `resolve(id)`.
 * - `{"$router": <routes>}` → `new Router(revive(<routes>))` (nested `$stone`s become live stones;
 *   plain strings pass through, since `RoutePathType` already treats a string as a `Files` shortcut).
 *
 * All transforms are non-mutating — a new value is always produced.
 */
@:expose
class ConfigReviver {

    /**
     * Recursively revive `value`, resolving `$stone`/`$router` sentinels. `resolve` owns lookup
     * policy and should throw (with the id in the message) when an id is unknown.
     */
    @:keep public static function revive(value:Dynamic, resolve:(id:String)->AnyStone):Dynamic {
        if (value == null) return null;
        if (value is Array) {
            var arr:Array<Dynamic> = value;
            return arr.map(item -> revive(item, resolve));
        }
        if (isPlainObject(value)) {
            var obj:DynamicAccess<Dynamic> = value;
            var keys = obj.keys();
            var hasStone = obj.exists("$stone");
            var hasRouter = obj.exists("$router");
            if (hasStone || hasRouter) {
                var sentinel = hasStone ? "$stone" : "$router";
                if (keys.length != 1)
                    throw new js.lib.Error('Malformed reference: an object with "' + sentinel
                        + '" must have no other keys, but has: ' + keys.join(", "));
                if (hasStone) {
                    var id:Dynamic = obj.get("$stone");
                    if (!(id is String))
                        throw new js.lib.Error("\"$stone\" value must be a string id, got: " + Std.string(id));
                    return resolve(id);
                } else {
                    return new Router(revive(obj.get("$router"), resolve));
                }
            }
            var result = new DynamicAccess<Dynamic>();
            for (key => v in obj) result.set(key, revive(v, resolve));
            return result;
        }
        return value; // primitives pass through
    }

    /**
     * Recursively collect all `$stone` id strings in a JSON value, deduped, in order of first
     * appearance. Descends into `$router` route arrays too. Used by StoneStore for topological
     * ordering and the dependent-update cascade.
     */
    @:keep public static function collectStoneRefs(value:Dynamic):Array<String> {
        var out:Array<String> = [];
        function walk(v:Dynamic):Void {
            if (v == null) return;
            if (v is Array) {
                for (item in (v:Array<Dynamic>)) walk(item);
                return;
            }
            if (isPlainObject(v)) {
                var obj:DynamicAccess<Dynamic> = v;
                if (obj.exists("$stone") && obj.keys().length == 1) {
                    var id:Dynamic = obj.get("$stone");
                    if (id is String && out.indexOf(id) == -1) out.push(id);
                    return;
                }
                for (_ => vv in obj) walk(vv);
            }
        }
        walk(value);
        return out;
    }

    /** Plain JSON object (not null, not an array, not a class instance). Mirrors ConfigStore. */
    static inline function isPlainObject(v:Dynamic):Bool {
        return v != null
            && js.Syntax.code('typeof {0} === "object"', v)
            && !(v is Array)
            && js.Syntax.code('(Object.getPrototypeOf({0}) === null || Object.getPrototypeOf({0}) === Object.prototype)', v);
    }

}
