package whet.stones;

import whet.Whetstone;

class HxmlStone extends Whetstone<HxmlConfig> {

    public var build:BuildStone;

    override function initConfig() {
        if (config.id == null) config.id = 'build';
        if (config.cacheStrategy == null) config.cacheStrategy = InFile(LimitCountByLastUse(1));
        build = new BuildStone({ hxml: this, id: 'build', project: config.project });
    }

    public function clone(id:WhetstoneId = null):HxmlStone {
        var cloneConfig = config.clone();
        cloneConfig.id = id;
        return new HxmlStone(cloneConfig);
    }

    public function mergeConfig(additionalConfig:HxmlConfig):HxmlStone {
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
        var args = config.libs.map(lib -> ['-lib', lib])
            .concat(config.paths.map(path -> ['-cp', path]))
            .concat(config.defines.map(def -> ['-D', def]));
        if (config.dce != null) args.push(['-dce', config.dce]);
        if (config.main != null) args.push(['-main', config.main]);
        if (config.debug == true) args.push(['-debug']);
        return args.concat(config.flags);
    }

    function getFileContent():String {
        return '# Generated from Whet library. Do not manually edit.\n' + getBuildArgs()
            .map(line -> line.join(' '))
            .join('\n');
    }

    @:allow(whet.stones.BuildStone) function getExportPath():SourceId {
        var dir = cache.getDir(build, build.getHash());
        return if (isSingleFile()) getFilename().getPutInDir(dir) else dir;
    }

    @:allow(whet.stones.BuildStone) function getFilename():SourceId {
        if (isSingleFile()) {
            var filename:SourceId = build.config.filename != null ? build.config.filename : 'build';
            if (filename.ext == "") filename.ext = getBuildExtension();
            return filename;
        } else throw "Not a single file.";
    }

    function getPlatform():Array<String> {
        var path = getExportPath().toRelPath('/'); // Not using `project` rel path, as we launch haxe in correct cwd.
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

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        var filename = list()[0];
        var path = filename.getPutInDir(cache.getDir(this, hash));
        Whet.msg('Generating hxml file in $path.');
        return [WhetSourceData.fromString(filename, getFileContent())];
    }

    override function list():Array<SourceId> {
        var filename:SourceId = id;
        if (filename.ext == "") filename.ext = "hxml";
        return [filename];
    }

    public override function generateHash():WhetSourceHash return WhetSourceHash.fromString(getBaseArgs().map(l -> l.join(' ')).join('\n'));

}

@:structInit class HxmlConfig extends WhetstoneConfig {

    public var libs:Array<String> = [];
    public var paths:Array<String> = [];
    public var defines:Array<String> = [];
    public var dce:DCE = null;
    public var main:String = null;
    public var debug:Null<Bool> = null;
    public var flags:Array<Array<String>> = [];
    public var platform:BuildPlatform = null;

    public function clone():HxmlConfig return {
        libs: this.libs.copy(),
        paths: this.paths.copy(),
        defines: this.defines.copy(),
        dce: this.dce,
        main: this.main,
        debug: this.debug,
        flags: [for (fa in this.flags) fa.copy()],
        platform: this.platform
    };

}

enum abstract DCE(String) to String {

    var STD = "std";
    var FULL = "full";
    var NO = "no";

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
