package whet;

@:using(whet.WhetSourceHash)
class WhetSourceHash {

    public static final EMPTY = {
        var bytes = haxe.io.Bytes.alloc(HASH_LENGTH);
        bytes.fill(0, HASH_LENGTH, 0);
        new WhetSourceHash(bytes);
    }

    static inline var HASH_LENGTH:Int = 20;

    final bytes:haxe.io.Bytes;

    function new(bytes:haxe.io.Bytes) {
        this.bytes = bytes;
    }

    public static function fromBytes(data:haxe.io.Bytes):WhetSourceHash {
        return new WhetSourceHash(haxe.crypto.Sha1.make(data));
    }

    public static function fromString(data:String):WhetSourceHash {
        return fromBytes(haxe.io.Bytes.ofString(data));
    }

    public static function add(a:WhetSourceHash, b:WhetSourceHash):WhetSourceHash {
        var data = haxe.io.Bytes.alloc(HASH_LENGTH * 2);
        data.blit(0, a.bytes, 0, HASH_LENGTH);
        data.blit(HASH_LENGTH, b.bytes, 0, HASH_LENGTH);
        return fromBytes(data);
    }

    public static function equals(a:WhetSourceHash, b:WhetSourceHash):Bool {
        return a != null && b != null && a.bytes.compare(b.bytes) == 0;
    }

    public static function toHex(hash:WhetSourceHash):String {
        return hash == null ? "" : hash.toString();
    }

    @:noCompletion public function toString():String return bytes.toHex();

    public static function fromHex(hex:String):WhetSourceHash {
        var hash = haxe.io.Bytes.ofHex(hex);
        if (hash.length != HASH_LENGTH) return null;
        else return new WhetSourceHash(hash);
    }

    public static function merge(...hash:WhetSourceHash):WhetSourceHash {
        var h = hash[0];
        for (i in 1...hash.length) h = h.add(hash[i]);
        return h;
    }

}
