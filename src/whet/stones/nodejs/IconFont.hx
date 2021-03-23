package whet.stones.nodejs;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import whet.npm.NpmManager;

class IconFont extends Whetstone<IconFontConfig> {

    public static final cssFile:SourceId = 'icons.css';
    public static final iconsSource:SourceId = 'font/';

    public function new(config:IconFontConfig) {
        if (config.cacheStrategy == null) config.cacheStrategy = CacheManager.defaultFileStrategy;
        super(config);
    }

    override function getHash():WhetSourceHash {
        var hash = WhetSourceHash.fromString(config.getArgs().join(''));
        if (FileSystem.exists(config.inputDirectory))
            for (filehash in FileSystem.readDirectory(config.inputDirectory).map(file ->
                WhetSourceHash.fromBytes(File.getBytes(Path.join([config.inputDirectory, file])))))
                hash = hash.add(filehash);
        return hash;
    }

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        trace('Generating icon font.');
        NpmManager.assureInstalled("fantasticon", "1.0.9");
        var out = CacheManager.getDir(this, hash);
        Utils.ensureDirExist(out);
        var args = config.getArgs().concat(['-o', out]);
        #if hxnodejs
        var cmd = js.node.Path.normalize(NpmManager.NODE_ROOT + 'fantasticon');
        js.node.ChildProcess.spawnSync(cmd, args, { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new Process(NpmManager.NODE_ROOT + 'fantasticon', args);
        p.exitCode();
        #end
        var res = [WhetSourceData.fromFile(cssFile, cssFile.getPutInDir(out))];
        for (ext in config.fontTypes) {
            var id:SourceId = 'icons.$ext';
            res.push(WhetSourceData.fromFile(id.getPutInDir(iconsSource), id.getPutInDir(out)));
        }
        return res;
    }

}

@:structInit class IconFontConfig extends WhetstoneConfig {

    /** `fantasicon` does not support multiple input files, just a directory. */
    public var inputDirectory:SourceId;

    /** -t, --font-types <value...>  specify font formats to generate (default: eot, woff2, woff, available: eot, woff2, woff, ttf, svg) */
    public var fontTypes:Array<IconFontType> = null;

    /** -g --asset-types <value...>  specify other asset types to generate (default: css, html, json, ts, available: css, html, json, ts) */
    public var assetTypes:Array<IconFontAsset> = null;

    /** -h, --font-height <value>    the output font height (icons will be scaled so the highest has this height) (default: 300) */
    public var fontHeight:Null<Int> = null;

    /** --descent <value>            the font descent */
    public var descent:Null<Int> = null;

    /** -n, --normalize              normalize icons by scaling them to the height of the highest icon */
    public var normalize:Null<Bool> = null;

    /** -r, --round                  setup the SVG path rounding [10e12] */
    /** --selector <value>           use a CSS selector instead of 'tag + prefix' (default: null) */
    public var selector:String = null;

    /** -t, --tag <value>            CSS base tag for icons (default: "i") */
    public var tag:String = null;

    /** -u, --fonts-url <value>      public url to the fonts directory (used in the generated CSS) (default: "./") */
    public var fontsUrl:String = null;

    public function getArgs():Array<String> {
        var args:Array<String> = [inputDirectory];
        if (fontTypes != null) args = args.concat(['-t']).concat(fontTypes);
        if (assetTypes != null) args = args.concat(['-g']).concat(assetTypes);
        if (fontHeight != null) args = args.concat(['-h', Std.string(fontHeight)]);
        if (descent != null) args = args.concat(['--descent', Std.string(descent)]);
        if (normalize) args.push('-n');
        if (selector != null) args = args.concat(['--selector', selector]);
        if (tag != null) args = args.concat(['-t', tag]);
        if (fontsUrl != null) args = args.concat(['-u', fontsUrl]);
        return args;
    }

}

enum abstract IconFontType(String) to String {

    var EOT = "eot";
    var WOFF2 = "woff2";
    var WOFF = "woff";
    var TTF = "ttf";
    var SVG = "svg";

}

enum abstract IconFontAsset(String) to String {

    var CSS = "css";
    var HTML = "html";
    var JSON = "json";
    var TS = "ts";

}
