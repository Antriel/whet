package whet.stones;

import haxe.DynamicAccess;

/**
 * Minimal, dependency-free JSON Schema (draft-07 subset) validator. Whet keeps deps minimal, so we
 * do not pull in ajv — this covers exactly what `configSchema()` needs to describe a stone's editable
 * config object, and nothing more.
 *
 * Supported keywords: `type` (string or array of strings), `properties`, `required`,
 * `additionalProperties` (boolean only), `items`, `enum`, `minimum`, `maximum`, `minLength`,
 * `pattern`. `description`/`default` are ignored (documentation). **Unknown keywords are ignored**
 * for forward-compatibility.
 *
 * A subtree whose value is a single-key `{"$stone": ...}` or `{"$router": ...}` object is **skipped**
 * (returns no findings): those sentinels revive into live stones/routers and legitimately mismatch
 * the JSON-shaped schema.
 */
@:expose
class SchemaValidator {

    /**
     * Validate `value` against `schema`, returning a (possibly empty) list of findings. Each finding
     * has a JSON-path-ish `path` (e.g. `outputs[0].id`, empty at the root) and a human `message`.
     * Collects all findings rather than failing fast, so callers can aggregate.
     */
    @:keep public static function validate(value:Dynamic, schema:Dynamic, ?path:String):Array<{path:String, message:String}> {
        var out:Array<{path:String, message:String}> = [];
        if (path == null) path = "";
        walk(value, schema, path, out);
        return out;
    }

    static function walk(value:Dynamic, schema:Dynamic, path:String, out:Array<{path:String, message:String}>):Void {
        if (schema == null || !isPlainObject(schema)) return;
        // Sentinels revive to live instances; never validate their JSON shape.
        if (isRefSentinel(value)) return;
        var s:DynamicAccess<Dynamic> = schema;

        if (s.exists("type")) {
            var t = s.get("type");
            var types:Array<String> = (t is Array) ? cast t : [cast t];
            if (!matchesAnyType(value, types)) {
                out.push({ path: path, message: 'expected type ${types.join(" or ")}, got ${jsonTypeOf(value)}' });
                return; // A type mismatch makes deeper checks meaningless / noisy.
            }
        }

        if (s.exists("enum")) {
            var allowed:Array<Dynamic> = s.get("enum");
            var ok = false;
            for (a in allowed) if (jsEquals(a, value)) { ok = true; break; }
            if (!ok) out.push({ path: path, message: 'value ${jsonStr(value)} is not one of the allowed values' });
        }

        if (value is String) {
            var str:String = value;
            if (s.exists("minLength") && str.length < (s.get("minLength"):Int))
                out.push({ path: path, message: 'string length ${str.length} is below minLength ${s.get("minLength")}' });
            if (s.exists("pattern")) {
                var pat:String = s.get("pattern");
                var re:Dynamic = try js.Syntax.code('new RegExp({0})', pat) catch (_:Dynamic) null;
                if (re != null && !(cast js.Syntax.code('{0}.test({1})', re, str)))
                    out.push({ path: path, message: 'string ${jsonStr(str)} does not match pattern /$pat/' });
            }
        }

        if (isNumber(value)) {
            var n:Float = value;
            if (s.exists("minimum") && n < (s.get("minimum"):Float))
                out.push({ path: path, message: 'value $n is below minimum ${s.get("minimum")}' });
            if (s.exists("maximum") && n > (s.get("maximum"):Float))
                out.push({ path: path, message: 'value $n is above maximum ${s.get("maximum")}' });
        }

        if (isPlainObject(value)) {
            var obj:DynamicAccess<Dynamic> = value;
            var props:DynamicAccess<Dynamic> = s.exists("properties") ? s.get("properties") : null;

            if (s.exists("required")) {
                var req:Array<String> = s.get("required");
                for (r in req) if (!obj.exists(r))
                    out.push({ path: path, message: 'missing required property "$r"' });
            }

            if (s.exists("additionalProperties") && s.get("additionalProperties") == false) {
                for (k in obj.keys())
                    if (props == null || !props.exists(k))
                        out.push({ path: joinPath(path, k), message: 'additional property "$k" is not allowed' });
            }

            if (props != null) {
                for (k => propSchema in props)
                    if (obj.exists(k)) walk(obj.get(k), propSchema, joinPath(path, k), out);
            }
        }

        if (value is Array && s.exists("items")) {
            var arr:Array<Dynamic> = value;
            var itemSchema = s.get("items");
            for (i in 0...arr.length) walk(arr[i], itemSchema, '$path[$i]', out);
        }
    }

    static inline function joinPath(path:String, key:String):String
        return path == "" ? key : '$path.$key';

    static function matchesAnyType(value:Dynamic, types:Array<String>):Bool {
        for (t in types) if (matchesType(value, t)) return true;
        return false;
    }

    static function matchesType(value:Dynamic, type:String):Bool {
        return switch (type) {
            case "string": value is String;
            case "number": isNumber(value);
            case "integer": isNumber(value) && (value:Float) == Math.ffloor(value);
            case "boolean": value is Bool;
            case "array": value is Array;
            case "object": isPlainObject(value);
            case "null": value == null;
            case _: true; // Unknown type name → don't flag.
        }
    }

    static function jsonTypeOf(value:Dynamic):String {
        if (value == null) return "null";
        if (value is String) return "string";
        if (value is Bool) return "boolean";
        if (isNumber(value)) return "number";
        if (value is Array) return "array";
        if (isPlainObject(value)) return "object";
        return "unknown";
    }

    static inline function jsonStr(value:Dynamic):String
        return try haxe.Json.stringify(value) catch (_:Dynamic) Std.string(value);

    static inline function isNumber(v:Dynamic):Bool
        return js.Syntax.code('typeof {0} === "number"', v);

    static inline function jsEquals(a:Dynamic, b:Dynamic):Bool
        return js.Syntax.code('{0} === {1}', a, b);

    /** Single-key `{$stone}` / `{$router}` object — revives to a live instance, skip validation. */
    static function isRefSentinel(v:Dynamic):Bool {
        if (!isPlainObject(v)) return false;
        var obj:DynamicAccess<Dynamic> = v;
        var keys = obj.keys();
        return keys.length == 1 && (keys[0] == "$stone" || keys[0] == "$router");
    }

    /** Plain JSON object (not null, not an array, not a class instance). Mirrors ConfigReviver. */
    static inline function isPlainObject(v:Dynamic):Bool {
        return v != null
            && js.Syntax.code('typeof {0} === "object"', v)
            && !(v is Array)
            && js.Syntax.code('(Object.getPrototypeOf({0}) === null || Object.getPrototypeOf({0}) === Object.prototype)', v);
    }

}
