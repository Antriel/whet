package whet;

import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
import sys.FileSystem;

class Whet {

    #if macro
    static var commands:Array<{command:String, argument:String}>;

    static macro function run() {
        // This is all ugly, based on previous design, but will do for now...
        // Assuming commands are just functions to execute, if they exists, or commands if not.
        // All this compiles into a main function with set of functions to execute, so we can export
        // and run plain js, without having to pass commands to it.
        // In the future we should maybe use tink_cli for the commands and stuff, and handle running node
        // with the same commands instead of this mess.
        commands = [for (key => value in Context.getDefines())
            if (key.indexOf('whet.') == 0 && key != 'whet.project') {
                command: key.substr('whet.'.length),
                argument: value
            }
        ];
        var funcs = [];
        var project = Context.definedValue('whet.project');
        if (project == null) {
            var projects = FileSystem.readDirectory('.')
                .filter(s -> StringTools.endsWith(s, '.hx') && StringTools.contains(s, 'Project'))
                .map(s -> StringTools.replace(s, '.hx', ''));
            switch projects.length {
                case 0: Context.error('No project to run found.', Context.currentPos());
                case 1: project = projects[0];
                case _: Context.error('Multiple projects found, specify one using `-D whet.project=Project`.', Context.currentPos());
            }
        }
        for (t in Context.getModule(project)) switch t {
            case TInst(_.get() => { kind: KModuleFields(module), statics: _.get() => fields }, _):
                for (f in fields) if (f.kind.match(FMethod(_))) {
                    var i = Lambda.findIndex(commands, c -> c.command.indexOf(f.name + "(") == 0);
                    if (i >= 0) {
                        var f = commands.splice(i, 1)[0].command;
                        f = StringTools.replace(f, ';', ',');
                        funcs.push(Context.parse('$project.$f', Context.currentPos()));
                    }
                }
            case _:
        }

        Context.defineType(macro class WhetMain {

            static function main() {
                var commands = $v{commands};
                $b{funcs};
                whet.Whet.executeProjects($v{commands});
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
    public static function executeProjects(commands:Array<{command:String, argument:String}>):Void {
        if (commands.length == 0) {
            msg('No command found. Use `-D whet.<command>=[arg]`.\nAvailable commands:');
            for (project in WhetProject.projects) for (meta in project.commandsMeta) {
                msg(meta.names.join(', '));
                if (meta.description != null) msg('   ' + meta.description);
            }
        }
        for (cmd in commands) {
            var executed = false;
            for (project in WhetProject.projects) {
                if (!project.commands.exists(cmd.command)) continue;
                project.commands.get(cmd.command).fnc(cmd.argument);
                executed = true;
                break;
            }
            if (!executed) error('Command "${cmd.command}" is not defined.');
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
