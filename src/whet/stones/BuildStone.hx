package whet.stones;

#if (sys || nodejs)
import sys.io.File;
#end

using whet.ArgTools;

class BuildStone extends whet.Whetstone {

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
            config.flags
        ]);
    }

    #if (sys || nodejs)
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

}

typedef HxmlConfig = {

    @:optional var libs:Array<String>;
    @:optional var paths:Array<String>;
    @:optional var defines:Array<String>;
    @:optional var dce:DCE;
    @:optional var main:String;
    @:optional var debug:Bool;
    @:optional var flags:Array<String>;

}

enum abstract DCE(String) to String {

    var STD = "std";
    var FULL = "full";
    var NO = "no";

}
