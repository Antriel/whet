package whet.stones.haxe;

import whet.magic.MaybeArray;

class HaxeBuild extends Stone<BuildConfig> {

    override function initConfig() {
        if (config.cacheStrategy == null) config.cacheStrategy = cache.defaultFileStrategy;
        config.cwd ??= js.node.Path.join(js.Node.process.cwd(), project.rootDir.toCwdPath('./'));
    }

    /** Build the given hxml. */
    public function build():Promise<Nothing> {
        final startTime = js.lib.Date.now();
        Log.info('Building Haxe project (id "${config.id}").');
        return new Promise(function(res, rej) {
            var cmd = Lambda.flatten(config.hxml.getBuildArgs());
            cmd.unshift(if (config.useNpx) 'npx haxe' else 'haxe');
            cmd = cmd.map(c -> StringTools.replace(c, '"', '\\"'));
            js.node.ChildProcess.exec(cmd.join(' '), cast {
                cwd: config.cwd,
                windowsHide: true
            }, function(err:js.lib.Error, stdout, stderr) {
                if (err != null) {
                    var haxeError = new js.lib.Error(stderr);
                    haxeError.name = "Haxe Build Error";
                    rej(haxeError);
                } else {
                    Log.info('Haxe build successful (id "${config.id}" in ${js.lib.Date.now() - startTime} ms).');
                    res(null);
                }
            });
        });
    }

    function generate(hash:SourceHash):Promise<Array<SourceData>> {
        if (config.hxml.isSingleFile()) {
            var pathId = config.hxml.getBuildExportPath();
            var path = pathId.toCwdPath(project);
            // Clear the file, so if compilation fails, we don't serve old version.
            return Utils.deleteAll(path).then(_ -> build()).then(_ -> {
                SourceData.fromFile(pathId.withExt, path, pathId).then(file -> {
                    return [file];
                });
            });
        } else {
            throw new js.lib.Error('Cannot get source of a multi-file build. Not implemented yet.');
        }
    }

    override function addCommands():Void {
        project.addCommand('build', this).action(_ -> this.cache.refreshSource(this));
    }

    override function list():Promise<Array<SourceId>> {
        if (config.hxml.isSingleFile()) {
            return Promise.resolve([config.hxml.getBuildFilename()]);
        } else return super.list();
    }

    override function generateHash():Promise<SourceHash> {
        // Not perfect, as it doesn't detect changes to library versions, but good enough.
        var paths = makeArray(config.hxml.config.paths).map(path -> js.node.Path.join(config.cwd, path));
        return Promise.all([config.hxml.getHash(), SourceHash.fromFiles(paths)])
            .then(r -> SourceHash.merge(...cast r));
    }

}

typedef BuildConfig = StoneConfig & {

    var hxml:Hxml;
    var ?useNpx:Bool;
    var ?filename:String;
    var ?cwd:String;

}
