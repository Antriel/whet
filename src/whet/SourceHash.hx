package whet;

import js.node.Buffer;
import js.node.Fs;
import whet.cache.HashCache;
import whet.magic.MaybeArray;

@:using(whet.SourceHash)
class SourceHash {

    public static final EMPTY = {
        var bytes = Buffer.alloc(HASH_LENGTH);
        new SourceHash(bytes);
    }

    static inline var HASH_LENGTH:Int = 32;

    final bytes:Buffer;

    function new(bytes:Buffer) {
        this.bytes = bytes;
    }

    public static function fromFile(path:String):Promise<SourceHash> {
        return HashCache.get().getFileHash(path);
    }

    /**
     * Creates hashes of all files and or content of directories, optionally recursive.
     */
    public static function fromFiles(paths:MaybeArray<String>, filter:String->Bool = null, recursive = true):Promise<SourceHash> {
        final allFilesProm = [for (src in makeArray(paths)) new Promise((res, rej) -> Fs.stat(src, function(err, stats) {
            if (err != null) rej(err);
            else if (stats.isDirectory()) Utils.listDirectoryFiles(src, recursive).then(files -> res(files));
            else res([src]);
        }))];
        return Promise.all(allFilesProm).then((arrFiles:Array<Array<String>>) -> {
            arrFiles.map(files -> {
                if (filter != null) files = files.filter(filter);
                (untyped files).sort(); // Keep deterministic.
                return (cast Promise.all(files.map(f -> SourceHash.fromFile(f))):Promise<Array<SourceHash>>);
            });
        }).then(proms -> Promise.all(proms))
            .then((allHashes:Array<Array<SourceHash>>) -> merge(...Lambda.flatten(allHashes)));
    }

    public static function fromBytes(data:Buffer):SourceHash {
        return new SourceHash(js.node.Crypto.createHash('sha256').update(data).digest());
    }

    public static function fromString(data:String):SourceHash {
        return fromBytes(Buffer.from(data));
    }

    /**
     * Converts `obj` to string via JSON.stringify, defaults to 'null' if undefined to prevent
     * errors. The string is then converted to hash. See also `fromConfig`.
     */
    @:keep public static function fromStringify(obj:Dynamic):SourceHash {
        return fromBytes(Buffer.from(haxe.Json.stringify(obj) ?? 'null'));
    }

    /**
     * Convert a Stone config into hash by ignoring the base `StoneConfig` fields
     * and anything inside `ignoreList`, getting hash of `Stone` and `Router` instances,
     * and applying `fromStringify` on the rest.
     * Only checks keys at root level, no deep inspection is done.
     */
    @:keep public static function fromConfig(obj:haxe.DynamicAccess<Dynamic>,
            ?ignoreList:Array<String>):Promise<SourceHash> {
        var keys = [];
        var hashes = [for (key => val in obj) switch key {
            case 'cacheStrategy' | 'id' | 'project' | 'dependencies': continue;
            case key if (ignoreList != null && ignoreList.contains(key)): continue;
            case _:
                keys.push(key);
                if (val is Stone) (val:AnyStone).getHash();
                else if (val is Router) (val:Router).getHash();
                else cast SourceHash.fromStringify(val);
        }];
        return Promise.all(hashes).then(hashes -> merge(...hashes));
    }

    public function add(hash:SourceHash):SourceHash {
        var data = Buffer.alloc(HASH_LENGTH * 2);
        this.bytes.copy(data, 0, 0, HASH_LENGTH);
        hash.bytes.copy(data, HASH_LENGTH, 0, HASH_LENGTH);
        return fromBytes(data);
    }

    public static function equals(a:SourceHash, b:SourceHash):Bool {
        return a != null && b != null && a.bytes.compare(b.bytes) == 0;
    }

    public static function toHex(hash:SourceHash):String {
        return hash == null ? "" : hash.toString();
    }

    @:noCompletion public function toString():String return bytes.toString('hex');

    public static function fromHex(hex:String):SourceHash {
        var hash = Buffer.from(hex, 'hex');
        if (hash.length != HASH_LENGTH) return null;
        else return new SourceHash(hash);
    }

    public static function merge(...hash:SourceHash):SourceHash {
        if (hash.length == 0) return SourceHash.EMPTY;
        var h = hash[0];
        for (i in 1...hash.length) h = h.add(hash[i]);
        return h;
    }

}
