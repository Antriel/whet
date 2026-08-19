package whet.stones.haxe;

import whet.magic.MaybeArray;

class HaxeBuild extends Stone<BuildConfig> {

    override function initConfig() {
        if (config.cacheStrategy == null) config.cacheStrategy = cache.defaultFileStrategy;
        config.cwd ??= js.node.Path.join(js.Node.process.cwd(), project.rootDir.toCwdPath('./'));
    }

    /**
     * Add default Haxe diagnostic settings without overriding hxml-defined values.
     * Console output stays plain; the optional log file is pretty and colored.
     * Keep these out of HxmlConfig so its hash and generated hxml stay portable.
     */
    function messageSetup():{args:Array<String>, logPath:Null<String>} {
        final existing = makeArray(config.hxml.config.defines);
        function unset(name:String)
            return !Lambda.exists(existing, d -> d == name || StringTools.startsWith(d, '$name='));
        var args = [];
        if (unset('message.reporting')) args = args.concat(['-D', 'message.reporting=classic']);
        // Color affects only the pretty log file.
        if (unset('message.color') && unset('message.no-color')) args = args.concat(['-D', 'message.color']);
        var logPath = null;
        if (unset('message.log-file')) {
            var safeId = ~/[^a-zA-Z0-9_\-.]/g.replace(config.id, '_');
            logPath = js.node.Path.resolve(config.cwd, '.whet/.temp/haxe-messages/$safeId.log');
            args = args.concat(['-D', 'message.log-file=$logPath']);
            if (unset('message.log-format')) args = args.concat(['-D', 'message.log-format=pretty']);
        }
        return { args: args, logPath: logPath };
    }

    /** Build the given hxml. */
    public function build():Promise<Nothing> {
        final startTime = js.lib.Date.now();
        Log.info('Building Haxe project (id "${config.id}").');
        final msg = messageSetup();
        // Haxe creates the file but not its parent directory.
        final ready = if (msg.logPath != null) Utils.ensureDirExist(js.node.Path.dirname(msg.logPath))
            else Promise.resolve(null);
        return ready.then(_ -> new Promise(function(res, rej) {
            var cmd = Lambda.flatten(config.hxml.getBuildArgs()).concat(msg.args);
            cmd.unshift(if (config.useNpx) 'npx haxe' else 'haxe');
            cmd = cmd.map(c -> StringTools.replace(c, '"', '\\"'));
            js.node.ChildProcess.exec(cmd.join(' '), cast {
                cwd: config.cwd,
                windowsHide: true
            }, function(err:js.lib.Error, stdout, stderr) {
                if (err != null) rej(makeBuildError(stderr, msg.logPath));
                else {
                    Log.info('Haxe build successful (id "${config.id}" in ${js.lib.Date.now() - startTime} ms).');
                    res(null);
                }
            });
        }));
    }

    /** Build a plain error for logs, with the pretty compiler output on `haxeLog`. */
    function makeBuildError(stderr:String, logPath:Null<String>):js.lib.Error {
        var plain = StringTools.trim(stderr != null ? stderr : '');
        var haxeError = new js.lib.Error('Haxe build failed (id "${config.id}").'
            + (plain.length > 0 ? '\n' + plain : ''));
        haxeError.name = "Haxe Build Error";
        // This callback stack is unhelpful and repeats the message.
        untyped haxeError.stack = null;
        // Fall back when no log file is available or configured.
        var pretty = if (logPath == null) null else try {
            var c:String = js.node.Fs.readFileSync(logPath, cast 'utf-8');
            StringTools.trim(c) != '' ? c : null;
        } catch (e:Dynamic) null;
        untyped haxeError.haxeLog = pretty != null ? pretty : plain;
        return haxeError;
    }

    override function generate(hash:SourceHash):Promise<Array<SourceData>> {
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
        if (this.config.exposeCommands != false)
        project.addCommand('build', this).action(_ -> this.cache.refreshSource(this));
    }

    override function list():Promise<Null<Array<SourceId>>> {
        if (config.hxml.isSingleFile()) {
            return Promise.resolve([config.hxml.getBuildFilename()]);
        } else return Promise.resolve(null);
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
    var ?exposeCommands:Bool;

}
