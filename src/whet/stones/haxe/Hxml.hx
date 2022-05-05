package whet.stones.haxe;

import whet.magic.MaybeArray;
import whet.magic.StoneId;

class Hxml extends Stone<HxmlConfig> {

    public var build:HaxeBuild;

    override function initConfig() {
        if (config.cacheStrategy == null) config.cacheStrategy = InFile(LimitCountByLastUse(1));
        build = new HaxeBuild({ hxml: this, id: 'build', project: config.project });
    }

    public function clone(id:StoneIdType = null):Hxml {
        var configClone = cloneConfig(config);
        configClone.id = makeStoneId(id);
        return new Hxml(configClone);
    }

    public function mergeConfig(additionalConfig:HxmlConfig):Hxml {
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

    public function getBuildArgs() return getBaseArgs().concat([getPlatform()]);

    function getBaseArgs():Array<Array<String>> {
        var args = makeArray(config.libs).map(lib -> ['-lib', lib])
            .concat(makeArray(config.paths).map(path -> ['-cp', path]))
            .concat(makeArray(config.defines).map(def -> ['-D', def]));
        if (config.dce != null) args.push(['-dce', switch config.dce {
            case STD: 'std';
            case FULL: 'full';
            case NO: 'no';
            case _: throw new js.lib.Error("Invalid DCE value.");
        }]);
        if (config.main != null) args.push(['-main', config.main]);
        if (config.debug == true) args.push(['-debug']);
        return args.concat(makeArray(config.flags).map(f -> makeArray(f)));
    }

    function getFileContent():String {
        return '# Generated from Whet library. Do not edit manually.\n' + getBuildArgs()
            .map(line -> line.join(' '))
            .join('\n');
    }

    @:allow(whet.stones.haxe.HaxeBuild) function getBuildExportPath():SourceId {
        var dir = cache.getDir(build, generateHashSync());
        return if (isSingleFile()) getBuildFilename().getPutInDir(dir) else dir;
    }

    @:allow(whet.stones.haxe.HaxeBuild) function getBuildFilename():SourceId {
        if (isSingleFile()) {
            var filename:SourceId = build.config.filename != null ? build.config.filename : 'build';
            if (filename.ext == "") filename.ext = getBuildExtension();
            return filename;
        } else throw new js.lib.Error("Not a single file.");
    }

    function getPlatform():Array<String> {
        var path = getBuildExportPath().toCwdPath('/'); // Not using `project` rel path, as we launch haxe in correct cwd.
        return switch config.platform {
            case null: [];
            case JS: ['-js', path];
            case SWF: ['-swf', path];
            case NEKO: ['-neko', path];
            case PHP: ['-php', path];
            case CPP: ['-cpp', path];
            case CS: ['-cs', path];
            case JAVA: ['-java', path];
            case PYTHON: ['-python', path];
            case LUA: ['-lua', path];
            case HL: ['-hl', path];
            case CPPIA: ['-cppia', path];
            case _: throw new js.lib.Error("Invalid platform value.");
        }
    }

    public function isSingleFile():Bool {
        return switch config.platform {
            case JS | SWF | NEKO | PYTHON | LUA | HL | CPPIA: true;
            case _: false;
        }
    }

    public function getBuildExtension():String {
        return switch config.platform {
            case JS: 'js';
            case SWF: 'swf';
            case NEKO: 'n';
            case PYTHON: 'py';
            case LUA: 'lua';
            case HL: 'hl';
            case CPPIA: 'cppia';
            case _: '';
        }
    }

    function generate(hash:SourceHash):Promise<Array<SourceData>> {
        Log.info('Generating hxml file.');
        return Promise.resolve([SourceData.fromString(cast filename(), getFileContent())]);
    }

    override function list():Promise<Array<SourceId>> {
        return Promise.resolve([filename()]);
    }

    function filename() {
        var fn:SourceId = id;
        if (fn.ext == "") fn.ext = "hxml";
        return fn;
    }

    public override function generateHash():Promise<SourceHash>
        return Promise.resolve(generateHashSync());

    public function generateHashSync():SourceHash
        return SourceHash.fromString(getBaseArgs().map(l -> l.join(' ')).join('\n'));

    function cloneConfig(config:HxmlConfig):HxmlConfig {
        return {
            project: config.project,
            libs: makeArray(config.libs).copy(),
            paths: makeArray(config.paths).copy(),
            defines: makeArray(config.defines).copy(),
            dce: config.dce,
            main: config.main,
            debug: config.debug,
            flags: [for (fa in makeArray(config.flags)) makeArray(fa).copy()],
            platform: config.platform
        };
    }

}

typedef HxmlConfig = StoneConfig & {

    var ?libs:MaybeArray<String>;
    var ?paths:MaybeArray<String>;
    var ?defines:MaybeArray<String>;
    var ?dce:DCE;
    var ?main:String;
    var ?debug:Null<Bool>;
    var ?flags:MaybeArray<MaybeArray<String>>;
    var ?platform:BuildPlatform;

}

enum DCE {

    STD;
    FULL;
    NO;

}

enum BuildPlatform {

    JS;
    SWF;
    NEKO;
    PHP;
    CPP;
    CS;
    JAVA;
    PYTHON;
    LUA;
    HL;
    CPPIA;

}
