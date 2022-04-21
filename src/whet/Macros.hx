package whet;

import haxe.macro.Context;
import haxe.macro.Expr;

using StringTools;
using sys.io.File;

class Macros {

    public static macro function getVersion():Expr {
        return macro $v{haxe.Json.parse(sys.io.File.getContent('package.json')).version};
    }

    public static macro function postprocess() {
        var prefix = '#!/usr/bin/env node\n';
        Context.onAfterGenerate(function() {
            var file = haxe.macro.Compiler.getOutput();

            switch file.getContent() {
                case _.startsWith(prefix) => true:
                case v:
                    file.saveContent(prefix + v);
            }

        });
        return null;
    }

}
