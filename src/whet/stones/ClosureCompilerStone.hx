package whet.stones;

import sys.FileSystem;
import whet.Whetstone;

#if closure
class ClosureCompilerStone extends Whetstone {

    var config:ClosureStoneConfig;

    public function new(project:WhetProject, config:ClosureStoneConfig) {
        super(project);
        this.config = config;
    }

    static var compilerPath:String = #if macro getCompilerPathImpl(); #else getCompilerPath(); #end

    public override function getSource():WhetSource {
        // TODO some kind of global cache system
        var startTime = Sys.time();
        var files = config.files.map(file -> {
            for (src in config.sources) {
                var fileSrc = src.findSource(file);
                if (fileSrc != null) return fileSrc;
            }
            Whet.error('Could not find source for $file.');
            return null;
        });
        Whet.msg('Closure compiling ${files.length} file${files.length == 1 ? "" : "s"}.');
        var totalSizeKB = 0;
        for (file in files) {
            totalSizeKB += file.lengthKB;
            Whet.msg('File ${file.getFilePath()} with size ${file.lengthKB} KB.');
        }

        var args = [
            '-jar', compilerPath,
            '--strict_mode_input=${config.strictMode}',
            '--compilation_level', config.compilationLevel,
            '--js_output_file', config.output,
            '--language_in', config.languageIn
        ];
        if (config.externs != null) args = args.concat(['--externs', config.externs]);
        if (config.warningLevel != null) args = args.concat(['--warning_level', config.warningLevel]);
        if (config.sourceMap != null) args = args.concat(['--create_source_map', config.sourceMap]);
        if (config.jscompOff != null) args.push('--jscomp_off=${config.jscompOff}');
        for (file in files) args = args.concat(['--js', file.getFilePath()]);

        return switch Sys.command('java', args) {
            case 0:
                var resource = WhetSource.fromFile(config.output);
                var totalTime = Sys.time() - startTime;
                var secondsRounded = Math.round(totalTime * 1000) / 1000;
                Whet.msg('Success. Merged in ${secondsRounded}s, final size ${resource.lengthKB} KB (-${totalSizeKB - resource.lengthKB} KB).');
                return resource;
            case error:
                Whet.msg('Closure compile failed with error code $error.');
                null;
        }
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

    public override function getSource():WhetSource {
        Whet.error('ClosureCompilerStone requires closure library.');
    }

}
#end

@:structInit class ClosureStoneConfig {

    public var files:Array<SourceId>;
    public var sources:Array<Whetstone>;
    public var strictMode:Bool = false;
    public var output:String = ".whet/merged.js";
    public var jscompOff:String = "es5Strict";
    public var compilationLevel:String = "SIMPLE";
    public var languageOut:String = "NO_TRANSPILE";
    public var languageIn:String = "ECMASCRIPT5";
    public var warningLevel:String = "QUIET";
    public var sourceMap:String = null;
    public var externs:String = null;

}
