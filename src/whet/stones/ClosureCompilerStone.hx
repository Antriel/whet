package whet.stones;

import sys.FileSystem;
import whet.Whetstone;

class ClosureCompilerStone extends Whetstone<ClosureCompilerConfig> {

    public static final mergedJs:SourceId = 'merged.js';

    public function new(config) {
        if (config.cacheStrategy == null) config.cacheStrategy = CacheManager.defaultFileStrategy;
        super(config);
    }

    #if closure
    static var compilerPath:String = #if macro getCompilerPathImpl(); #else getCompilerPath(); #end

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        var startTime = Sys.time();
        var files = config.sources.getData();
        Whet.msg('Closure compiling ${files.length} file${files.length == 1 ? "" : "s"}.');
        var totalSizeKB = 0;
        for (file in files) {
            totalSizeKB += file.lengthKB;
            Whet.msg('File ${file.getFilePath()} with size ${file.lengthKB} KB.');
        }

        var output = mergedJs.getPutInDir(CacheManager.getDir(this, hash));
        var args = getArgs(files.map(f -> f.getFilePath()), output);

        return switch Sys.command('java', args) {
            case 0:
                var resource = WhetSourceData.fromFile(output.withExt, output);
                var totalTime = Sys.time() - startTime;
                var secondsRounded = Math.round(totalTime * 1000) / 1000;
                Whet.msg('Success. Merged in ${secondsRounded}s, final size ${resource.lengthKB} KB (-${totalSizeKB - resource.lengthKB} KB).');
                return [resource];
            case error:
                Whet.msg('Closure compile failed with error code $error.');
                null;
        }
    }

    override function getHash():WhetSourceHash {
        var hash = WhetSourceHash.fromString(getArgs([], "").join(''));
        return hash.add(config.sources.getHash());
    }

    function getArgs(filePaths:Array<SourceId>, outputPath:String):Array<String> {
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

    macro static function getCompilerPath() return macro $v{getCompilerPathImpl()};

    #if macro
    static function getCompilerPathImpl() {
        var path = haxe.macro.Context.resolvePath("closure/Compiler.hx");
        path = haxe.io.Path.directory(path) + '/cli/compiler.jar';
        return path;
    }
    #end
    #else
    override function generateSource():WhetSource {
        Whet.error('ClosureCompilerStone requires closure library.');
        return null;
    }
    #end

}

@:structInit class ClosureCompilerConfig extends WhetstoneConfig {

    public var sources:Route;
    public var strictMode:Bool = false;
    public var jscompOff:String = "es5Strict";
    public var compilationLevel:String = "SIMPLE";
    public var languageOut:String = "NO_TRANSPILE";
    public var languageIn:String = "ECMASCRIPT5";
    public var warningLevel:String = "QUIET";
    public var sourceMap:String = null;
    public var externs:String = null;

}
