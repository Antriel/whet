package whet.stones.nodejs;

import sys.io.Process;
import whet.npm.NpmManager;

class CssAutoprefixer extends Whetstone<CssAutoprefixerConfig> {

    public function new(config:CssAutoprefixerConfig) {
        if (config.cacheStrategy == null) config.cacheStrategy = CacheManager.defaultFileStrategy;
        super(config);
    }

    override function getHash():WhetSourceHash {
        return config.css.getHash();
    }

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        trace('Auto-prefixing css.');
        NpmManager.assureInstalled("postcss-cli", "7.1.1");
        NpmManager.assureInstalled("autoprefixer", "9.8.0");
        // postcss --use autoprefixer --map false --dir out-css/ css/bulma.css [...css]
        var dir = CacheManager.getDir(this, hash);
        Utils.ensureDirExist(dir);
        var args:Array<String> = ['--use', 'autoprefixer', '--map', 'false', '--dir', dir];
        var data = config.css.getData();
        for (item in data) args.push(item.getFilePath());
        #if hxnodejs
        var cmd = js.node.Path.normalize(NpmManager.NODE_ROOT + 'postcss');
        js.node.ChildProcess.spawnSync(cmd, args, { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new Process(NpmManager.NODE_ROOT + 'postcss', args);
        p.exitCode();
        #end
        return [for (item in data) {
            var baseId:SourceId = item.id.withExt;
            WhetSourceData.fromFile(baseId, baseId.getPutInDir(dir));
        }];
    }

}

@:structInit class CssAutoprefixerConfig extends WhetstoneConfig {

    /**
     * Route for one or more css files.
     * **Warning:** Their base names need to be unique.
     */
    public var css:Route;

}
