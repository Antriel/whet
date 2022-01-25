package whet;

import haxe.DynamicAccess;
import haxe.Json;

@:expose class Log {

    public static inline function trace(...args:Dynamic) return log(10, ...args);

    public static inline function debug(...args:Dynamic) return log(20, ...args);

    public static inline function info(...args:Dynamic) return log(30, ...args);

    public static inline function warn(...args:Dynamic) return log(40, ...args);

    public static inline function error(...args:Dynamic) return log(50, ...args);

    public static inline function fatal(...args:Dynamic) return log(60, ...args);

    public static var logLevel:LogLevel = Info;

    static function log(level:Int, ...args:Dynamic):Void {
        if (level >= (logLevel:Int)) {
            var out:DynamicAccess<Dynamic> = cast {
                level: level,
                time: js.lib.Date.now(),
                msg: null
            };
            for (arg in args) {
                if (arg == null) continue;
                if (arg is String) {
                    if (out['msg'] == null) out['msg'] = arg;
                    else if (out['msg'] is String) out['msg'] = [out['msg'], arg];
                    else (out['msg']:Array<String>).push(arg);
                } else {
                    var obj:DynamicAccess<Dynamic> = cast arg;
                    for (field => value in obj) out[field] = value;
                }
            }
            js.Node.process.stdout.write(Json.stringify(out, replacer) + '\n');
        }
    }

    static function replacer(key:Dynamic, val:Dynamic):Dynamic {
        if (val != null && js.Lib.typeof(val.toString) == 'function' && val.toString != js.lib.Object.prototype.toString)
            return val.toString();
        return val;
    }

}

enum abstract LogLevel(Int) to Int from Int {

    var Trace = 10;
    var Debug = 20;
    var Info = 30;
    var Warn = 40;
    var Error = 50;
    var Fatal = 60;

    public static function normalize(i:Int):LogLevel {
        return if (i < (Debug:Int)) Trace;
        else if (i < (Info:Int)) Debug;
        else if (i < (Warn:Int)) Info;
        else if (i < (Error:Int)) Warn;
        else if (i < (Fatal:Int)) Error;
        else Fatal;
    }

    @:to public function toString():String {
        return switch normalize(this) {
            case Trace: "trace";
            case Debug: "debug";
            case Info: "info";
            case Warn: "warn";
            case Error: "error";
            case Fatal: "fatal";
        }
    }

    @:from public static function fromString(s:String):Null<LogLevel> {
        return switch s.toLowerCase() {
            case "trace": Trace;
            case "debug": Debug;
            case "info": Info;
            case "warn": Warn;
            case "error": Error;
            case "fatal": Fatal;
            case _: null;
        }
    }

}
