package whet.stones;

import whet.Whetstone;

class BuildStone extends Whetstone {

    public var config:BuildConfig;

    public function new(project:WhetProject, id:WhetstoneID = null, config:BuildConfig) {
        if (id == null) id = project.config.id;
        super(project, id, CacheManager.defaultFileStrategy);
        if (config.hxml.isSingleFile()) {
            defaultFilename = 'build.${config.hxml.getBuildExtension()}';
        }
        this.config = config;
    }

    /** Build the given hxml. */
    @command public function build() {
        Sys.command('haxe', Lambda.flatten(config.hxml.getBuildArgs()));
    }

    override function generateSource():WhetSource {
        if (config.hxml.isSingleFile()) {
            build();
            return WhetSource.fromFile(this, CacheManager.getFilePath(this), getHash());
        } else {
            Whet.msg('Warning: Cannot get source of a multi-file build.');
            return null;
            // Multi-file builds should be used by routing the files (not implemented).
            // That could be wrapped in some ZipStone or something similar, as needed.
        }
    }

    override function getHash():WhetSourceHash {
        return config.hxml.getHash();
        // Technically not correct, but real solution isn't feasible.
    }

}

@:structInit class BuildConfig {

    public var hxml:HxmlStone;

}
