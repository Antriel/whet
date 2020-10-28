package whet;

import haxe.io.Path;
import sys.FileSystem;

using StringTools;

class Utils {

    public static function argToArray(arg:String):Array<String> {
        if (arg == '1') return [];
        if (arg.startsWith('[') && arg.endsWith(']')) {
            arg = arg.substring(1, arg.length - 1);
        }
        return arg.split(',').map(a -> a.replace(' ', '')).filter(a -> a.length > 0);
    }

    public static inline function makeUnique<T>(val:T, isNotUnique:T->Bool, modify:(val:T, variant:Int) -> T):T {
        var unique = val;
        var counter = 0;
        while (isNotUnique(unique))
            unique = modify(val, ++counter);
        return unique;
    }

    public static inline function makeUniqueString(s:String, isNotUnique:String->Bool):String
        return makeUnique(s, isNotUnique, (s, v) -> s + v);

    public static function ensureDirExist(path:String):Void {
        var fullPath = "";
        for (dir in haxe.io.Path.directory(path).split('/')) {
            fullPath += '$dir/';
            if (!sys.FileSystem.exists(fullPath)) sys.FileSystem.createDirectory(fullPath);
        }
    }

    /** Same as `sys.io.File.saveContent`, but also creates missing directories. */
    public static function saveContent(path:String, content:String):Void {
        ensureDirExist(path);
        sys.io.File.saveContent(path, content);
    }

    /** Same as `sys.io.File.saveBytes`, but also creates missing directories. */
    public static function saveBytes(path:String, bytes:haxe.io.Bytes):Void {
        ensureDirExist(path);
        sys.io.File.saveBytes(path, bytes);
    }

    /** Deletes the path, recursively if it's a directory. */
    public static function deleteRecursively(path:String):Void {
        if (FileSystem.exists(path)) {
            if (FileSystem.isDirectory(path)) {
                for (file in FileSystem.readDirectory(path)) deleteRecursively(Path.join([path, file]));
                FileSystem.deleteDirectory(path);
            } else {
                FileSystem.deleteFile(path);
            }
        }
    }

}
