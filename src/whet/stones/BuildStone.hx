package whet.stones;

class BuildStone extends FileWhetstone<BuildConfig> {

    /** Build the given hxml. */
    @command public function build() {
        var cwd = Sys.getCwd();
        Sys.setCwd(haxe.io.Path.join([cwd, project.rootDir.toRelPath('/')]));
        Sys.command('haxe', Lambda.flatten(config.hxml.getBuildArgs()));
        Sys.setCwd(cwd);
    }

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        if (config.hxml.isSingleFile()) {
            var pathId = config.hxml.getExportPath();
            var path = pathId.toRelPath(project);
            // Clear the file, so if compilation fails, we don't serve old version.
            if (sys.FileSystem.exists(path)) sys.FileSystem.deleteFile(path);
            build();
            return [WhetSourceData.fromFile(pathId.withExt, path, pathId)];
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
