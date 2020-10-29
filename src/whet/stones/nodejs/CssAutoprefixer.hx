package whet.stones.nodejs;

import sys.io.Process;
import whet.Whetstone;
import whet.npm.NpmManager;

class CssAutoprefixer extends Whetstone {

    public var css:Whetstone;

    public function new(project:WhetProject, id:WhetstoneID = null, css:Whetstone) {
        super(project, id, CacheManager.defaultFileStrategy);
        this.css = css;
    }

    override function getHash():WhetSourceHash {
        return css.getHash();
    }

    override function generateSource():WhetSource {
        trace('Auto-prefixing css.');
        NpmManager.assureInstalled("postcss-cli", "7.1.1");
        NpmManager.assureInstalled("autoprefixer", "9.8.0");
        var hash = getHash();
        // postcss --use autoprefixer --map false --output css/bulma.css css/bulma.css
        var out = CacheManager.getFilePath(this, 'prefixed.css', hash);
        Utils.ensureDirExist(out.dir);
        var args:Array<String> = ['--use', 'autoprefixer', '--map', 'false', '--output', out, css.getSource().getFilePath()];
        #if hxnodejs
        var cmd = js.node.Path.normalize(NpmManager.NODE_ROOT + 'postcss');
        js.node.ChildProcess.spawnSync(cmd, args, { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new Process(NpmManager.NODE_ROOT + 'postcss', args);
        p.exitCode();
        #end
        return WhetSource.fromFile(this, out, hash);
    }

}
