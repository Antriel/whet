package whet;

import haxe.DynamicAccess;
import haxe.macro.Compiler;
import haxe.macro.Expr;
import haxe.macro.Context;

class Whet {

    #if macro
    static var commands:Array<{command:String, argument:String}>;
    static var config:DynamicAccess<String>;

    static function getProject():WhetProject {
        return untyped new Project(config);
        // For some reason Type.resolveClass doesn't work, so we can't do this dynamically.
    }

    static macro function run() {
        commands = [for (key => value in Context.getDefines())
            if (key.indexOf('whet.') == 0) if (key == 'whet.config') {
                config = Lambda.fold(value.split(',').map(c -> c.split('=')), (c, r:DynamicAccess<String>) -> {
                    r.set(c[0], c[1]);
                    r;
                }, new DynamicAccess<String>());
                continue;
            } else {
                command: key.substr('whet.'.length),
                argument: value
            }
        ];
        if (config == null) config = {};

        Context.defineType(macro class WhetMain {

            static function main() {
                var commands = $v{commands};
                var project = new Project($v{config});
                whet.Whet.executeProject(project, $v{commands});
            }

        });
        if (Context.defined('hxnodejs') && Sys.args().indexOf('--no-output') == -1) // Don't run in diagnostics/display context.
            Context.onAfterGenerate(function() {
                Sys.command('node', [Compiler.getOutput()]);
            });
        return null;
    }
    #end

    @:noCompletion
    public static function executeProject(project:WhetProject, commands:Array<{command:String, argument:String}>):Void {
        if (commands.length == 0) {
            msg('No command found. Use `-D whet.<command>=[arg]`.\nAvailable commands:');
            for (meta in project.commandsMeta) {
                msg(meta.names.join(', '));
                if (meta.description != null) msg('   ' + meta.description);
            }
        }
        for (cmd in commands) {
            if (!project.commands.exists(cmd.command)) error('Command "${cmd.command}" is not defined.');
            project.commands.get(cmd.command).fnc(cmd.argument);
        }
    }

    public static function error(msg:String):Void {
        #if (sys || hxnodejs)
        Sys.stderr().writeString('Error: ' + msg);
        Sys.exit(1);
        #else
        throw 'Error: $msg';
        #end
    }

    public static function msg(msg:String):Void {
        #if (sys || hxnodejs)
        Sys.stdout().writeString(msg + '\n');
        #if sys
        Sys.stdout().flush();
        #end
        #else
        trace(msg);
        #end
    }

}
