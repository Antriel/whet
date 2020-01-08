package whet.stones;

import sys.FileSystem;
import whet.Whetstone;

#if closure
class ClosureCompilerStone extends Whetstone {

    var config:ClosureStoneConfig;

    public function new(project:WhetProject, config:ClosureStoneConfig) {
        super(project);
        this.cacheMode = MemoryCache; // TODO use File one
        this.config = config;
    }

    static var compilerPath:String = #if macro getCompilerPathImpl(); #else getCompilerPath(); #end

    public override function generateSource():WhetSource {
        var startTime = Sys.time();
        var files = getFiles().map(s -> s.getSource());
        Whet.msg('Closure compiling ${files.length} file${files.length == 1 ? "" : "s"}.');
        var totalSizeKB = 0;
        for (file in files) {
            totalSizeKB += file.lengthKB;
            Whet.msg('File ${file.getFilePath()} with size ${file.lengthKB} KB.');
        }

        var output = CacheManager.getFilePath(this, 'merged.js');
        var args = getArgs(files.map(f -> f.getFilePath()), output);

        return switch Sys.command('java', args) {
            case 0:
                var resource = WhetSource.fromFile(output, getHash());
                var totalTime = Sys.time() - startTime;
                var secondsRounded = Math.round(totalTime * 1000) / 1000;
                Whet.msg('Success. Merged in ${secondsRounded}s, final size ${resource.lengthKB} KB (-${totalSizeKB - resource.lengthKB} KB).');
                return resource;
            case error:
                Whet.msg('Closure compile failed with error code $error.');
                null;
        }
    }

    override function getHash():WhetSourceHash {
        var hash:WhetSourceHash = getArgs([], "").join('');
        for (file in getFiles()) hash += file.getHash();
        return hash;
    }

    function getArgs(filePaths:Array<String>, outputPath:String):Array<String> {
        var args = [
            '-jar', compilerPath,
            '--strict_mode_input=${config.strictMode}',
            '--compilation_level', config.compilationLevel,
            '--js_output_file', outputPath,
            '--language_in', config.languageIn,
            '--language_out', config.languageOut
        ];
        if (config.externs != null) args = args.concat(['--externs', config.externs]);
        if (config.warningLevel != null) args = args.concat(['--warning_level', config.warningLevel]);
        if (config.sourceMap != null) args = args.concat(['--create_source_map', config.sourceMap]);
        if (config.jscompOff != null) args.push('--jscomp_off=${config.jscompOff}');
        for (path in filePaths) args = args.concat(['--js', path]);
        return args;
    }

    function getFiles():Array<Whetstone> {
        return config.files.map(file -> {
            for (src in config.sources) {
                var fileStone = src.findStone(file);
                if (fileStone != null) return fileStone;
            }
            Whet.error('Could not find source for $file.');
            return null;
        });
    }

    macro static function getCompilerPath() return macro $v{getCompilerPathImpl()};

    #if macro
    static function getCompilerPathImpl() {
        var path = haxe.macro.Context.resolvePath("closure/Compiler.hx");
        path = haxe.io.Path.directory(path) + '/cli/compiler.jar';
        return path;
    }
    #end

}
#else
class ClosureCompilerStone extends Whetstone {

    public function new(project:WhetProject, config:ClosureStoneConfig) {
        super(project);
    }

    public override function generateSource():WhetSource {
        Whet.error('ClosureCompilerStone requires closure library.');
        return null;
    }

}
#end

@:structInit class ClosureStoneConfig {

    public var files:Array<SourceId>;
    public var sources:Array<Whetstone>;
    public var strictMode:Bool = false;
    public var jscompOff:String = "es5Strict";
    public var compilationLevel:String = "SIMPLE";
    public var languageOut:String = "NO_TRANSPILE";
    public var languageIn:String = "ECMASCRIPT5";
    public var warningLevel:String = "QUIET";
    public var sourceMap:String = null;
    public var externs:String = null;

}
