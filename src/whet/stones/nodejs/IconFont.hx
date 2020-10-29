package whet.stones.nodejs;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import whet.Whetstone;
import whet.npm.NpmManager;
import whet.stones.FileStone.AsyncFileStone;

class IconFont extends Whetstone {

    public final config:IconFontConfig;

    public function new(project:WhetProject, id:WhetstoneID = null, config:IconFontConfig) {
        super(project, id, CacheManager.defaultFileStrategy);
        this.config = config;
        var dir = getDir(getHash());
        // TODO this isn't great. If the input folder content changes, we don't update the dir, which depends on the hash...
        // We could re-route whenever we calculate hash, and it's different than our previous one.
        this.route([for (ext in config.fontTypes) {
            var id:SourceId = 'icons.$ext';
            id => (new AsyncFileStone(this, id.getPutInDir(dir)):Whetstone);
        }]);
    }

    override function getHash():WhetSourceHash {
        var hash = WhetSourceHash.fromString(config.getArgs().join(''));
        if (FileSystem.exists(config.inputDirectory))
            for (filehash in FileSystem.readDirectory(config.inputDirectory).map(file ->
                WhetSourceHash.fromBytes(File.getBytes(Path.join([config.inputDirectory, file])))))
                hash = hash.add(filehash);
        return hash;
    }

    override function generateSource():WhetSource {
        trace('Generating icon font.');
        NpmManager.assureInstalled("fantasticon", "1.0.9");
        // TODO should properly think out and implement folder-based caching.
        var hash = getHash();
        var out = getDir(hash);
        Utils.ensureDirExist(out);
        var args = config.getArgs().concat(['-o', out]);
        #if hxnodejs
        var cmd = js.node.Path.normalize(NpmManager.NODE_ROOT + 'fantasticon');
        js.node.ChildProcess.spawnSync(cmd, args, { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new Process(NpmManager.NODE_ROOT + 'fantasticon', args);
        p.exitCode();
        #end
        return WhetSource.fromFile(this, out + 'icons.css', hash);
    }

    function getDir(hash:WhetSourceHash) return CacheManager.getFilePath(this, 'icons/', hash);

}

// Everything needs to be final because config defines what routes we have available.
// If we need changes, we need to implement re-routing.
@:structInit class IconFontConfig {

    public final inputDirectory:SourceId;

    /** -t, --font-types <value...>  specify font formats to generate (default: eot, woff2, woff, available: eot, woff2, woff, ttf, svg) */
    public final fontTypes:Array<IconFontType> = null;

    /** -g --asset-types <value...>  specify other asset types to generate (default: css, html, json, ts, available: css, html, json, ts) */
    public final assetTypes:Array<IconFontAsset> = null;

    /** -h, --font-height <value>    the output font height (icons will be scaled so the highest has this height) (default: 300) */
    public final fontHeight:Null<Int> = null;

    /** --descent <value>            the font descent */
    public final descent:Null<Int> = null;

    /** -n, --normalize              normalize icons by scaling them to the height of the highest icon */
    public final normalize:Null<Bool> = null;

    /** -r, --round                  setup the SVG path rounding [10e12] */
    /** --selector <value>           use a CSS selector instead of 'tag + prefix' (default: null) */
    public final selector:String = null;

    /** -t, --tag <value>            CSS base tag for icons (default: "i") */
    public final tag:String = null;

    /** -u, --fonts-url <value>      public url to the fonts directory (used in the generated CSS) (default: "./") */
    public final fontsUrl:String = null;

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
