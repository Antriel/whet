package whet.stones.nodejs;

import sys.io.Process;
import whet.Whetstone;
import whet.npm.NpmManager;

class PurifyCss extends Whetstone {

    public final config:PurifyCssConfig;

    public function new(project:WhetProject, id:WhetstoneID = null, config:PurifyCssConfig) {
        super(project, id, CacheManager.defaultFileStrategy);
        this.config = config;
    }

    override function getHash():WhetSourceHash {
        var whitelist = config.whitelist != null ? config.whitelist.join('') : '';
        var hash = WhetSourceHash.fromString(config.minify + whitelist);
        for (content in config.content) hash = hash.add(content.getHash());
        for (css in config.cssInput) hash = hash.add(css.getHash());
        return hash;
    }

    override function generateSource():WhetSource {
        trace('Purifying css.');
        NpmManager.assureInstalled("purify-css", "1.2.5");
        var hash = getHash();
        // purifycss <css> <content> [option]
        var args:Array<String> = config.cssInput.concat(config.content).map(s -> s.getSource().getFilePath().toRelPath());
        if (config.minify) args.push('-m');
        if (config.whitelist != null) args = args.concat(['-w']).concat([for (w in config.whitelist) w]);
        var out = CacheManager.getFilePath(this, 'purified.css', hash);
        args = args.concat(['-o', out]);
        Utils.ensureDirExist(out.dir);
        #if hxnodejs
        var cmd = js.node.Path.normalize(NpmManager.NODE_ROOT + 'purifycss');
        js.node.ChildProcess.spawnSync(cmd, args, { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new Process(NpmManager.NODE_ROOT + 'purifycss', args);
        p.exitCode();
        #end
        return WhetSource.fromFile(this, out, hash);
    }

}

@:structInit class PurifyCssConfig {

    public var cssInput:Array<Whetstone>;

    /** JS or HTML content to use for static analysis of usage. */
    public var content:Array<Whetstone>;

    /** -m, --min        Minify CSS [boolean] [default: false] */
    public var minify:Bool = null;

    /** -o, --out        Filepath to write purified css to [string] */
    /** -w, --whitelist  List of classes that should not be removed [array] [default: []] */
    public var whitelist:Array<String> = null;

}
