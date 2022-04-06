package whet;

import haxe.macro.Context;
import haxe.macro.Expr;

class Macros {

    public static macro function getVersion():Expr {
        return macro $v{haxe.Json.parse(sys.io.File.getContent('package.json')).version};
    }

}
