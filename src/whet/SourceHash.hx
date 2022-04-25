package whet;

import js.node.Buffer;
import js.node.Fs;

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
        return new Promise((res, rej) -> Fs.readFile(path, (err, bytes) -> {
            if (err != null) rej(err);
            else res(fromBytes(bytes));
        }));
    }

    public static function fromBytes(data:Buffer):SourceHash {
        return new SourceHash(js.node.Crypto.createHash('sha256').update(data).digest());
    }

    public static function fromString(data:String):SourceHash {
        return fromBytes(Buffer.from(data));
    }

    public static function add(a:SourceHash, b:SourceHash):SourceHash {
        var data = Buffer.alloc(HASH_LENGTH * 2);
        a.bytes.copy(data, 0, 0, HASH_LENGTH);
        b.bytes.copy(data, HASH_LENGTH, 0, HASH_LENGTH);
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
