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
        if (hxmlPath == null) hxmlPath = '.whet/build.hxml';
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
            ['# Generated from Whet library. Do not manually edit.'],
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
            case JS(file): ['-js $file'];
            case SWF(file): ['-swf $file'];
            case NEKO(file): ['-neko $file'];
            case PHP(directory): ['-php $directory'];
            case CPP(directory): ['-cpp $directory'];
            case CS(directory): ['-cs $directory'];
            case JAVA(directory): ['-java $directory'];
            case PYTHON(file): ['-python $file'];
            case LUA(file): ['-lua $file'];
            case HL(file): ['-hl $file'];
            case CPPIA(file): ['-cppia $file'];
        }
    }

    function getBuildPath():String {
        return switch config.build {
            case JS(file) | SWF(file) | NEKO(file) | PYTHON(file) | LUA(file) | HL(file) | CPPIA(file): file;
            case _: throw "Not supported for this build.";
        }
    }

    @command public function hxml(_) {
        Whet.msg('Generating hxml file.');
        var hxmlArgs = getArgs();
        File.saveContent(hxmlPath, hxmlArgs.join('\n'));
        Whet.msg('Generated $hxmlPath.');
    }

    @command public function build(configs:String) {
        trace('running build with $configs');
    }

    public override function getSource():WhetSource {
        // TODO mode, cached, just-relay file, always new...
        // Use global cache system, default mode to 'fresh cache' i.e. compile once per startup of whet.
        // The cache should/could be on the core level, i.e. no stone needs to actually deal with it, it's abstracted away
        // I.e. when getting source from something it automatically goes through the cache, and every stine has settings that
        // can be changed.
        // invalidation: when something uses something, it gets dirty when dependencies are dirty
        // saving data to files, store temp var based on source name+hash in .whet/.ephemeral folder.
        var path = getBuildPath();
        if (sys.FileSystem.exists(path))
            return WhetSource.fromFile(path);
        else return null;
    }

}

@:structInit class HxmlConfig {

    public var libs:Array<String> = [];
    public var paths:Array<String> = [];
    public var defines:Array<String> = [];
    public var dce:DCE = null;
    public var main:String = null;
    public var debug:Bool = false;
    public var flags:Array<String> = [];
    public var build:BuildPlatform = null;

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
