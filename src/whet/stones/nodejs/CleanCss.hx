package whet.stones.nodejs;

import sys.io.Process;
import whet.npm.NpmManager;

class CleanCss extends FileWhetstone<CleanCssConfig> {

    public static final cleanCss:SourceId = 'clean.css';

    override function generateHash():WhetSourceHash {
        return config.css.getHash();
    }

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        trace('Cleaning css.');
        NpmManager.assureInstalled(project, "clean-css-cli", "4.3.0");
        // cleancss -o css/bulma.min.css css/bulma.css
        var dirId = cache.getDir(this, hash);
        var dir = dirId.toRelPath(project);
        Utils.ensureDirExist(dir);
        var outId = cleanCss.getPutInDir(dirId);
        var out = outId.toRelPath(project);
        var args:Array<String> = ['--skip-rebase', '-o', out].concat(
            config.css.getData().map(s -> s.getFilePath()));
        #if hxnodejs
        var cmd = js.node.Path.normalize(NpmManager.getNodeRoot(project) + 'node_modules/.bin/cleancss');
        js.node.ChildProcess.spawnSync(cmd, args, { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new Process(NpmManager.getNodeRoot(project) + 'node_modules/.bin/cleancss', args);
        p.exitCode();
        #end
        return [WhetSourceData.fromFile(cleanCss, out, outId)];
    }

    override function list():Array<SourceId> {
        return [cleanCss];
    }

}

@:structInit class CleanCssConfig extends WhetstoneConfig {

    public var css:Route;

}
