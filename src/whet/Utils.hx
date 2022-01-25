package whet;

import js.node.Buffer;
import js.node.Fs;
import js.node.Path;

using StringTools;

class Utils {

    public static inline function makeUnique<T>(val:T, isNotUnique:T->Bool, modify:(val:T, variant:Int) -> T):T {
        var unique = val;
        var counter = 0;
        while (isNotUnique(unique))
            unique = modify(val, ++counter);
        return unique;
    }

    public static inline function makeUniqueString(s:String, isNotUnique:String->Bool):String
        return makeUnique(s, isNotUnique, (s, v) -> s + v);

    public static function ensureDirExist(path:String):Promise<Nothing> {
        final dir = Path.dirname(path);
        Log.trace('Ensuring directory $dir exists.');
        return new Promise((res, rej) -> Fs.stat(dir, (err, stats) -> {
            if (err != null) {
                Fs.mkdir(dir, untyped { recursive: true },
                    err -> if (err != null) rej(err) else res(Nil));
            } else if (!stats.isDirectory()) {
                rej(new js.lib.Error("Path exists, but is not a directory."));
            } else res(null);
        }));
    }

    /** Saves string as UTF-8, creates missing directories if needed. */
    public static function saveContent(path:String, content:String):Promise<Nothing> {
        return saveBytes(path, Buffer.from(content, 'utf-8'));
    }

    /** Saves bytes Buffer, creates missing directories if needed. */
    public static function saveBytes(path:String, bytes:Buffer):Promise<Nothing> {
        Log.trace('Writing bytes to $path.');
        return ensureDirExist(path).then(_ -> new Promise((res,
                rej) -> Fs.writeFile(path, bytes, err -> if (err != null) rej(err) else res(null))
        ));
    }

}

enum abstract Nothing(Dynamic) {

    var Nil = null;

}
