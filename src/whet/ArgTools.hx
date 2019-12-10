package whet;

using StringTools;

class ArgTools {
    
    public static function toArray(arg:String):Array<String> {
        if(arg == '1') return [];
        if(arg.startsWith('[') && arg.endsWith(']')) {
            arg = arg.substring(1, arg.length-1);
        }
        return arg.split(',').map(a -> a.replace(' ', '')).filter(a -> a.length > 0);
    }
    
}
