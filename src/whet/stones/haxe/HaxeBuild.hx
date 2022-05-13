package whet.stones.haxe;

import whet.magic.MaybeArray;

class HaxeBuild extends Stone<BuildConfig> {

    override function initConfig() {
        if (config.cacheStrategy == null) config.cacheStrategy = cache.defaultFileStrategy;
    }

    /** Build the given hxml. */
    public function build():Promise<Nothing> {
        Log.info("Building Haxe project.");
        return new Promise(function(res, rej) {
            final cwd = js.node.Path.join(js.Node.process.cwd(), project.rootDir.toCwdPath('/'));
            var cmd = Lambda.flatten(config.hxml.getBuildArgs());
            cmd.unshift(if (config.useNpx) 'npx haxe' else 'haxe');
            cmd = cmd.map(c -> StringTools.replace(c, '"', '\\"'));
            js.node.ChildProcess.exec(cmd.join(' '), cast {
                cwd: cwd,
                windowsHide: true
            }, function(err, stdout, stderr) {
                if (err != null) rej(err);
                else res(null);
            });
        });
    }

    function generate(hash:SourceHash):Promise<Array<SourceData>> {
        if (config.hxml.isSingleFile()) {
            var pathId = config.hxml.getBuildExportPath();
            var path = pathId.toCwdPath(project);
            // Clear the file, so if compilation fails, we don't serve old version.
            return Utils.deleteAll(path).then(_ -> build()).then(_ -> {
                SourceData.fromFile(cast pathId.withExt, path, cast pathId).then(file -> {
                    return [file];
                });
            });
        } else {
            throw new js.lib.Error('Cannot get source of a multi-file build. Not implemented yet.');
        }
    }

    override function addCommands():Void {
        project.addCommand('build', this).action(_ -> build());
    }

    override function list():Promise<Array<SourceId>> {
        if (config.hxml.isSingleFile()) {
            return Promise.resolve([config.hxml.getBuildFilename()]);
        } else return super.list();
    }

    override function generateHash():Promise<SourceHash> {
        // Not perfect, as it doesn't detect changes to library versions, but good enough.
        var paths = makeArray(config.hxml.config.paths).map(path -> (path:SourceId).toCwdPath(config.hxml.project));
        return Promise.all([config.hxml.generateHash(), SourceHash.fromFiles(paths)])
            .then(r -> SourceHash.merge(...cast r));
    }

}

typedef BuildConfig = StoneConfig & {

    var hxml:Hxml;
    var ?useNpx:Bool;
    var ?filename:String;

}
