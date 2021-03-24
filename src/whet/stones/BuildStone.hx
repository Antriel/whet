package whet.stones;

class BuildStone extends Whetstone<BuildConfig> {

    public function new(config:BuildConfig) {
        if (config.cacheStrategy == null) config.cacheStrategy = CacheManager.defaultFileStrategy;
        super(config);
    }

    /** Build the given hxml. */
    @command public function build() {
        Sys.command('haxe', Lambda.flatten(config.hxml.getBuildArgs()));
    }

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        if (config.hxml.isSingleFile()) {
            var path = config.hxml.getExportPath();
            // Clear the file, so if compilation fails, we don't serve old version.
            if (sys.FileSystem.exists(path)) sys.FileSystem.deleteFile(path);
            build();
            return [WhetSourceData.fromFile(path.withExt, path)];
        } else {
            throw 'Cannot get source of a multi-file build. Not implemented yet.';
        }
    }

    override function list():Array<SourceId> {
        if (config.hxml.isSingleFile()) {
            return [config.hxml.getFilename()];
        } else return super.list();
    }

    override function generateHash():WhetSourceHash {
        return config.hxml.getHash();
        // Technically not correct, but real solution isn't feasible.
        // TODO why not, let's try hashing all the source files! :)
    }

}

@:structInit class BuildConfig extends WhetstoneConfig {

    public var hxml:HxmlStone;
    public var filename:SourceId = null;

}
