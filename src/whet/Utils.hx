package whet;

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
}
