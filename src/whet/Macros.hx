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

    public static macro function injectConfig():Array<Field> {
        var fields = Context.getBuildFields();
        var config = null;
        var configDefine = Context.getDefines().get('whet.config');
        if (configDefine != null) config = [for (keyVal in configDefine.split(',').map(c -> c.split('='))) keyVal[0] => keyVal[1]];
        if (config == null) return fields;

        var newFuncExprs = switch Lambda.find(fields, f -> f.name == 'new').kind {
            case FFun({ expr: { expr: EBlock(exprs) } }): exprs;
            case _: null;
        }
        for (f in fields) if (f.meta != null) {
            if (Lambda.exists(f.meta, m -> m.name == ":config" || m.name == "config")) {
                var val = config.get(f.name);
                val = StringTools.replace(val, ';', ',');
                if (config.remove(f.name)) switch f.kind {
                    case FVar(t, null):
                        newFuncExprs.unshift(macro $i{f.name} = $e{Context.parse(val, f.pos)});
                    case _:
                }
            }
        }
        for (key in config.keys()) Whet.msg('Warning: config $key is unused.');
        return fields;
    }

}
