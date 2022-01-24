package whet.stones.nodejs;

import sys.io.Process;
import whet.npm.NpmManager;

class CssAutoprefixer extends FileWhetstone<CssAutoprefixerConfig> {

    override function generateHash():WhetSourceHash {
        return config.css.getHash();
    }

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        trace('Auto-prefixing css.');
        NpmManager.assureInstalled(project, "postcss-cli", "7.1.1");
        NpmManager.assureInstalled(project, "autoprefixer", "9.8.0");
        // postcss --use autoprefixer --map false --dir out-css/ css/bulma.css [...css]
        var dirId = cache.getDir(this, hash);
        var dir = dirId.toRelPath(project);
        Utils.ensureDirExist(dir);
        var args:Array<String> = ['--use', 'autoprefixer', '--map', 'false', '--dir', dir];
        var data = config.css.getData();
        for (item in data) args.push(item.getFilePath());
        #if hxnodejs
        var cmd = js.node.Path.normalize(NpmManager.getNodeRoot(project) + 'node_modules/.bin/postcss');
        js.node.ChildProcess.spawnSync(cmd, args, { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new Process(NpmManager.getNodeRoot(project) + 'node_modules/.bin/postcss', args);
        p.exitCode();
        #end
        return [for (item in data) {
            var baseId:SourceId = item.id.withExt;
            var pathid = baseId.getPutInDir(dirId);
            WhetSourceData.fromFile(baseId, pathId.toRelPath(project), pathId);
        }];
    }

    override function list():Array<SourceId> {
        return [for (item in config.css.getData()) item.id.withExt];
    }

}

@:structInit class CssAutoprefixerConfig extends WhetstoneConfig {

    /**
     * Route for one or more css files.
     * **Warning:** Their base names need to be unique.
     */
    public var css:Route;

}
