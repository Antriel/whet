package whet.stones;

#if sys
import sys.io.File;
#end
using whet.ArgTools;

class BuildStone extends whet.Whetstone {
    
    var base:HxmlConfig;
    var configs:Map<String, HxmlConfig>;
    var hxmlPath:String;
    
    public function new(project:WhetProject, baseConfig:HxmlConfig, hxmlPath:String = null) {
        super(project);
        base = baseConfig;
        configs = new Map();
        if(hxmlPath == null) hxmlPath = 'build.hxml';
        this.hxmlPath = hxmlPath;
    }
    
    public function addConfig(name:String, config:HxmlConfig):BuildStone {
        configs.set(name, config);
        return this;
    }
    
    public function getArgs(configs:Array<String> = null):Array<String> {
        var libs:Array<String> = [];
        var paths:Array<String> = [];
        var defines:Array<String> = [];
        var dce:DCE = null;
        var main:String = null;
        var debug:Bool = false;
        var flags:Array<String> = [];
        function merge<T>(from:Array<T>, to:Array<T>)
            if(from != null) for(item in from) if(to.indexOf(item) == -1) to.push(item);
        if(configs == null) configs = [];
        for(config in configs) if(!this.configs.exists(config))
            whet.Whet.error('Config "$config" was not defined in project.');
        for(config in [base].concat([for(config in configs) this.configs[config]])) {
            merge(config.libs, libs);
            merge(config.paths, paths);
            merge(config.defines, defines);
            merge(config.flags, flags);
            if(config.dce != null) dce = config.dce;
            if(config.main != null) main = config.main;
            if(config.debug != null) debug = config.debug;
        }
        return Lambda.flatten([
            libs.map(lib -> '-lib $lib'),
            paths.map(path -> '-cp $path'),
            defines.map(def -> '-D $def'),
            dce != null ? ['-dce $dce'] : [],
            main != null ? ['-main $main'] : [],
            debug == true ? ['-debug'] : [],
            flags
        ]); 
    }
    
    #if sys
    @command public function hxml(configs:String) {
        var configs = configs.toArray();
        Whet.msg('Generating hxml file with configurations: $configs.');
        var hxmlArgs = getArgs(configs);
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
