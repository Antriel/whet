package whet.stones.nodejs;

import sys.io.Process;
import whet.npm.NpmManager;

class CleanCss extends Whetstone<CleanCssConfig> {

    public static final cleanCss:SourceId = 'clean.css';

    public function new(config) {
        if (config.cacheStrategy == null) config.cacheStrategy = CacheManager.defaultFileStrategy;
        super(config);
    }

    override function generateHash():WhetSourceHash {
        return config.css.getHash();
    }

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        trace('Cleaning css.');
        NpmManager.assureInstalled("clean-css-cli", "4.3.0");
        // cleancss -o css/bulma.min.css css/bulma.css
        var dir = CacheManager.getDir(this, hash);
        Utils.ensureDirExist(dir);
        var out = cleanCss.getPutInDir(dir);
        var args:Array<String> = ['--skip-rebase', '-o', out.toRelPath()].concat(
            config.css.getData().map(s -> s.getFilePath().toRelPath()));
        #if hxnodejs
        var cmd = js.node.Path.normalize(NpmManager.NODE_ROOT + 'cleancss');
        js.node.ChildProcess.spawnSync(cmd, args, { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new Process(NpmManager.NODE_ROOT + 'cleancss', args);
        p.exitCode();
        #end
        return [WhetSourceData.fromFile(cleanCss, out)];
    }

    override function list():Array<SourceId> {
        return [cleanCss];
    }

}

@:structInit class CleanCssConfig extends WhetstoneConfig {

    public var css:Route;

}
