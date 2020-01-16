package whet;

import haxe.macro.Context;
import haxe.macro.Expr;

class Macros {

    public static macro function addDocsMeta():Array<Field> {
        var fields = Context.getBuildFields();
        for (f in fields) if (f.meta != null) {
            var commandMeta = Lambda.find(f.meta, m -> m.name == "command");
            if (commandMeta != null) {
                switch f.kind {
                    case FFun(fun):
                        commandMeta.params = [
                            fun.args.length == 1 ? macro true : macro false,
                            macro $v{f.doc}
                        ];
                    case _:
                }
            }
        }
        return fields;
    }

}
