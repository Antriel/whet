package whet;

import haxe.macro.Compiler;
import haxe.macro.Expr;
import haxe.macro.Context;

class Whet {
    
    #if macro
    
    static var commands:Array<{command:String, argument:String}>;
    
    static function getProject():WhetProject {
        return untyped new Project();
        // For some reason Type.resolveClass doesn't work, so we can't do this dynamically.
    }
    
    static macro function run() {
        commands = [for(key => value in Context.getDefines())
            if(key.indexOf('whet.') == 0) {
                command: key.substr('whet.'.length),
                argument: value
            }
        ];
        
        if(Context.defined('hxnodejs')) {
            compileAndRun();
        } else {//interpret
            executeProject(getProject(), commands);
        }
        return null;
    }
    
    static function compileAndRun() {
        Context.defineType(macro class WhetMain {
            static function main() {
                var commands = $v{commands};
                var project = new Project();
                whet.Whet.executeProject(new Project(), $v{commands});
            }
        });
        Context.onAfterGenerate(function() {
            Sys.command('node', [Compiler.getOutput()]);
        });
    }
    
    #end
    
    @:noCompletion
    public static function executeProject(project:WhetProject, commands:Array<{command:String, argument:String}>):Void {
        if(commands.length == 0) {
            msg('No command found. Use `-D whet.<command>=[args]`.\nAvailable commands: ${[for(key in project.commands.keys()) key]}');
        }
        for(cmd in commands) {
            if(!project.commands.exists(cmd.command)) error('Command "${cmd.command}" is not defined.');
            project.commands.get(cmd.command)(cmd.argument);
        }
    }
    
    public static function error(msg:String):Void {
        #if (sys || nodejs)
        Sys.stderr().writeString('Error: '+msg);
        Sys.exit(1);
        #else
        throw 'Error: $msg';
        #end
    }
    
    public static function msg(msg:String):Void {
        #if (sys || nodejs)
        Sys.stdout().writeString(msg+'\n');
        #else
        trace(msg);
        #end
    }
    
    
}
