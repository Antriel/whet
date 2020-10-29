package whet.stones.nodejs;

import sys.io.Process;
import whet.Whetstone;
import whet.npm.NpmManager;

class CleanCss extends Whetstone {

    public var css:Whetstone;

    public function new(project:WhetProject, id:WhetstoneID = null, css:Whetstone) {
        super(project, id, CacheManager.defaultFileStrategy);
        this.css = css;
    }

    override function getHash():WhetSourceHash {
        return css.getHash();
    }

    override function generateSource():WhetSource {
        trace('Cleaning css.');
        NpmManager.assureInstalled("clean-css-cli", "4.3.0");
        var hash = getHash();
        // cleancss -o css/bulma.min.css css/bulma.css
        var out = CacheManager.getFilePath(this, 'clean.css', hash);
        Utils.ensureDirExist(out.dir);
        var args:Array<String> = ['--skip-rebase', '-o', out, css.getSource().getFilePath()];
        #if hxnodejs
        var cmd = js.node.Path.normalize(NpmManager.NODE_ROOT + 'cleancss');
        js.node.ChildProcess.spawnSync(cmd, args, { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new Process(NpmManager.NODE_ROOT + 'cleancss', args);
        p.exitCode();
        #end
        return WhetSource.fromFile(this, out, hash);
    }

}
