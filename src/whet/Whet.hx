package whet;

import haxe.macro.Expr;
import haxe.macro.Context;

class Whet {
    
    #if macro
    
    static function getProject():WhetProject {
        return untyped new Project();
        // For some reason Type.resolveClass doesn't work, so we can't do this dynamically.
    }
    
    static macro function run() {
        var project = getProject();
        var hasCommand = false;
        for(key => value in Context.getDefines()) {
            if(key.indexOf('whet.') == 0) {
                hasCommand = true;
                var command = key.substr('whet.'.length);
                if(!project.commands.exists(command)) error('Command "$command" is not defined.');
                trace(project.commands.get(command));
                trace(value);
                project.commands.get(command)(value);
            }
        }
        if(!hasCommand) {
            Sys.stdout().writeString('No command found. Use `-D whet.<command>=[args]`.\nAvailable commands: ${[for(key in project.commands.keys()) key]}');
        }
        return null;
    }
    
    #end
    
    public static function error(msg:String):Void {
        #if sys
        Sys.stderr().writeString('Error: '+msg);
        Sys.exit(1);
        #else
        throw 'Error: $msg';
        #end
    }
    
    public static function msg(msg:String):Void {
        #if sys
        Sys.stdout().writeString(msg+'\n');
        #else
        trace(msg);
        #end
    }
    
    
}
