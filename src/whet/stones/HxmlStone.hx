package whet.stones;

import whet.SourceId;
import whet.Whetstone;
import sys.io.File;

class HxmlStone extends Whetstone {

    public var config:HxmlConfig;
    public var build:BuildStone;

    public function new(project:WhetProject, id:WhetstoneID = null, config:HxmlConfig) {
        super(project, id != null ? id : project.config.id + '.hxml', InFile(LimitCountByLastUse(1)));
        this.config = config != null ? config : {};
        build = new BuildStone(project, id != null ? id + '.build' : null, { hxml: this });
        defaultFilename = 'build.hxml';
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

    function getPlatform():Array<String> {
        var path = CacheManager.getFilePath(build, build.getHash());
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

    override function generateSource():WhetSource {
        Whet.msg('Generating hxml file in ${CacheManager.getFilePath(this)}.');
        return WhetSource.fromString(this, getFileContent(), null);
    }

    public override function getHash():WhetSourceHash return WhetSourceHash.fromString(getBaseArgs().map(l -> l.join(' ')).join('\n'));

}

@:structInit class HxmlConfig {

    public var libs:Array<String> = [];
    public var paths:Array<String> = [];
    public var defines:Array<String> = [];
    public var dce:DCE = null;
    public var main:String = null;
    public var debug:Null<Bool> = null;
    public var flags:Array<Array<String>> = [];
    public var platform:BuildPlatform = null;

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
