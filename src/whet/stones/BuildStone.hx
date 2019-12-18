package whet.stones;

import whet.SourceId;
import whet.Whetstone;
#if (sys || hxnodejs)
import sys.io.File;
#end

using whet.ArgTools;

class BuildStone extends Whetstone {

    var config:HxmlConfig;
    var hxmlPath:String;

    public function new(project:WhetProject, config:HxmlConfig, hxmlPath:String = null) {
        super(project);
        this.config = config;
        if (hxmlPath == null) hxmlPath = 'build.hxml';
        this.hxmlPath = hxmlPath;
    }

    public function mergeConfig(additionalConfig:HxmlConfig):BuildStone {
        function merge<T>(from:Array<T>, to:Array<T>)
            if (from != null) for (item in from) if (to.indexOf(item) == -1) to.push(item);

        merge(additionalConfig.libs, config.libs);
        merge(additionalConfig.paths, config.paths);
        merge(additionalConfig.defines, config.defines);
        merge(additionalConfig.flags, config.flags);
        if (additionalConfig.dce != null) config.dce = additionalConfig.dce;
        if (additionalConfig.main != null) config.main = additionalConfig.main;
        if (additionalConfig.debug != null) config.debug = additionalConfig.debug;
        return this;
    }

    public function getArgs():Array<String> {
        return Lambda.flatten([
            config.libs.map(lib -> '-lib $lib'),
            config.paths.map(path -> '-cp $path'),
            config.defines.map(def -> '-D $def'),
            config.dce != null ? ['-dce ${config.dce}'] : [],
            config.main != null ? ['-main ${config.main}'] : [],
            config.debug == true ? ['-debug'] : [],
            getBuild(),
            config.flags
        ]);
    }

    function getBuild():Array<String> {
        return switch config.build {
            case null: [];
            case JS(file): ['-js', file];
            case SWF(file): ['-swf', file];
            case NEKO(file): ['-neko', file];
            case PHP(directory): ['-php', directory];
            case CPP(directory): ['-cpp', directory];
            case CS(directory): ['-cs', directory];
            case JAVA(directory): ['-java', directory];
            case PYTHON(file): ['-python', file];
            case LUA(file): ['-lua', file];
            case HL(file): ['-hl', file];
            case CPPIA(file): ['-cppia', file];
        }
    }

    function getBuildPath():String {
        return switch config.build {
            case JS(file) | SWF(file) | NEKO(file) | PYTHON(file) | LUA(file) | HL(file) | CPPIA(file): file;
            case _: throw "Not supported for this build.";
        }
    }

    #if (sys || hxnodejs)
    @command public function hxml(_) {
        Whet.msg('Generating hxml file.');
        var hxmlArgs = getArgs();
        File.saveContent(hxmlPath, hxmlArgs.join('\n'));
        Whet.msg('Generated $hxmlPath.');
    }

    @command public function build(configs:String) {
        trace('running build with $configs');
    }
    #end

    #if tink_io
    public override function getSource():WhetSource {
        // TODO mode, cached, just-relay file, always new...
        var path = getBuildPath();
        if (sys.FileSystem.exists(path))
            return sys.io.File.getBytes(path);
        else return null;
    }
    #end

}

typedef HxmlConfig = {

    @:optional var libs:Array<String>;
    @:optional var paths:Array<String>;
    @:optional var defines:Array<String>;
    @:optional var dce:DCE;
    @:optional var main:String;
    @:optional var debug:Bool;
    @:optional var flags:Array<String>;
    @:optional var build:BuildPlatform;

}

enum abstract DCE(String) to String {

    var STD = "std";
    var FULL = "full";
    var NO = "no";

}

enum BuildPlatform {

    JS(file:SourceId);
    SWF(file:SourceId);
    NEKO(file:SourceId);
    PHP(directory:SourceId);
    CPP(directory:SourceId);
    CS(directory:SourceId);
    JAVA(directory:SourceId);
    PYTHON(file:SourceId);
    LUA(file:SourceId);
    HL(file:SourceId);
    CPPIA(file:SourceId);

}
