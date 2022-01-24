package whet.stones.nodejs;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import whet.npm.NpmManager;

class IconFont extends FileWhetstone<IconFontConfig> {

    public static final cssFile:SourceId = 'icons.css';
    public static final iconsSource:SourceId = 'font/';

    override function generateHash():WhetSourceHash {
        var hash = WhetSourceHash.fromString(config.getArgs(true).join(''));
        var inputDir = config.inputDirectory.toRelPath(project);
        if (FileSystem.exists(inputDir))
            for (filehash in FileSystem.readDirectory(inputDir).map(file ->
                WhetSourceHash.fromBytes(File.getBytes(Path.join([inputDir, file])))))
                hash = hash.add(filehash);
        return hash;
    }

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        trace('Generating icon font.');
        NpmManager.assureInstalled(project, "fantasticon", "1.0.9");
        var outSource = cache.getDir(this, hash);
        var out = outSource.toRelPath(project);
        Utils.ensureDirExist(out);
        var args = config.getArgs().concat(['-o', out]);
        #if hxnodejs
        var cmd = js.node.Path.normalize(NpmManager.getNodeRoot(project) + 'node_modules/.bin/fantasticon');
        js.node.ChildProcess.spawnSync(cmd, args, { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new Process(NpmManager.getNodeRoot(project) + 'node_modules/.bin/fantasticon', args);
        p.exitCode();
        #end
        var cssPathId = cssFile.getPutInDir(outSource);
        var res = [WhetSourceData.fromFile(cssFile, cssPathId.toRelPath(project), cssPathId)];
        for (ext in config.fontTypes) {
            var id:SourceId = 'icons.$ext';
            var pathId = id.getPutInDir(outSource);
            res.push(WhetSourceData.fromFile(id.getPutInDir(iconsSource), pathId.toRelPath(project), pathId));
        }
        return res;
    }

    override function list():Array<SourceId> {
        return [cssFile].concat([for (ext in config.fontTypes) {
            var id:SourceId = 'icons.$ext';
            id.getPutInDir(iconsSource);
        }]);
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

    public function getArgs(forHash = false):Array<String> {
        var args:Array<String> = forHash ? [] : [inputDirectory.toRelPath(project)];
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
