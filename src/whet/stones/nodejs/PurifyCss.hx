package whet.stones.nodejs;

import sys.io.Process;
import whet.Whetstone;
import whet.npm.NpmManager;

class PurifyCss extends Whetstone<PurifyCssConfig> {

    public static final purifiedCss:SourceId = 'purified.css';

    public function new(config:PurifyCssConfig) {
        if (config.cacheStrategy == null) config.cacheStrategy = CacheManager.defaultFileStrategy;
        super(config);
    }

    override function generateHash():WhetSourceHash {
        var whitelist = config.whitelist != null ? config.whitelist.join('') : '';
        return WhetSourceHash.merge(
            WhetSourceHash.fromString(config.minify + whitelist),
            config.content.getHash(),
            config.cssInput.getHash()
        );
    }

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        trace('Purifying css.');
        NpmManager.assureInstalled("purify-css", "1.2.5");
        // purifycss <css> <content> [option]
        var args = config.cssInput.getData().concat(config.content.getData()).map(s -> s.getFilePath().toRelPath());
        if (config.minify) args.push('-m');
        if (config.whitelist != null) args = args.concat(['-w']).concat([for (w in config.whitelist) w]);
        var out = purifiedCss.getPutInDir(CacheManager.getDir(this, hash));
        args = args.concat(['-o', out]);
        Utils.ensureDirExist(out.dir);
        #if hxnodejs
        var cmd = js.node.Path.normalize(NpmManager.NODE_ROOT + 'purifycss');
        js.node.ChildProcess.spawnSync(cmd, args, { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new Process(NpmManager.NODE_ROOT + 'purifycss', args);
        p.exitCode();
        #end
        return [WhetSourceData.fromFile(purifiedCss, out)];
    }

    override function list():Array<SourceId> {
        return [purifiedCss];
    }

}

@:structInit class PurifyCssConfig extends WhetstoneConfig {

    public var cssInput:Route;

    /** JS or HTML content to use for static analysis of usage. */
    public var content:Route;

    /** -m, --min        Minify CSS [boolean] [default: false] */
    public var minify:Null<Bool> = null;

    /** -o, --out        Filepath to write purified css to [string] */
    /** -w, --whitelist  List of classes that should not be removed [array] [default: []] */
    public var whitelist:Array<String> = null;

}
