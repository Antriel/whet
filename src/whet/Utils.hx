package whet;

import js.node.Buffer;
import js.node.Fs;
import js.node.Path;

using StringTools;

@:expose
class Utils {

    public static inline function makeUnique<T>(val:T, isNotUnique:T->Bool, modify:(val:T, variant:Int) -> T):T {
        var unique = val;
        var counter = 0;
        while (isNotUnique(unique))
            unique = modify(val, ++counter);
        return unique;
    }

    public static inline function makeUniqueString(s:String, isNotUnique:String->Bool):String
        return makeUnique(s, isNotUnique, (s, v) -> s + v);

    public static function ensureDirExist(dir:String):Promise<Nothing> {
        Log.trace('Ensuring directory $dir exists.');
        return new Promise((res, rej) -> Fs.stat(dir, (err, stats) -> {
            if (err != null) {
                Fs.mkdir(dir, untyped { recursive: true },
                    err -> if (err != null) rej(err) else res(Nil));
            } else if (!stats.isDirectory()) {
                rej(new js.lib.Error("Path exists, but is not a directory."));
            } else res(null);
        }));
    }

    /** Saves string as UTF-8, creates missing directories if needed. */
    public static function saveContent(path:String, content:String):Promise<Nothing> {
        return saveBytes(path, Buffer.from(content, 'utf-8'));
    }

    /** Saves bytes Buffer, creates missing directories if needed. */
    public static function saveBytes(path:String, bytes:Buffer):Promise<Nothing> {
        Log.trace('Writing bytes to "$path".');
        return ensureDirExist(Path.dirname(path)).then(_ -> new Promise((res,
                rej) -> Fs.writeFile(path, bytes, err -> if (err != null) rej(err) else res(null))
        ));
    }

    public static function deleteAll(path:String):Promise<Nothing> {
        return new Promise((res,
                rej) -> js.Syntax.code(
                '{0}.rm({1}, {2}, {3})', Fs, path, { recursive: true, force: true }, _ -> res(null)));
    }

    /**
     * Scan `dir` (project-root-relative) recursively for files whose path relative to `dir` (posix
     * separators) matches `pattern` (a JS RegExp source). Dot-directories and `node_modules` are
     * skipped. Returns matched files as project-root-relative posix paths, plus a derived name per
     * file — `nameTemplate` with `$n` capture-group substitution (default `$1`), falling back to the
     * file stem when the template yields no capture. Both arrays are sorted by file path and aligned
     * by index.
     *
     * Ported near-verbatim from the game pipeline's `AudioDb.scanFiles`; kept semantically identical
     * so `AudioDb` can later migrate onto this helper.
     */
    public static function scanFiles(projectRoot:String, dir:String, pattern:String,
            ?nameTemplate:String):Promise<{files:Array<String>, names:Array<String>}> {
        if (nameTemplate == null) nameTemplate = '$1';
        var regex = new js.lib.RegExp(pattern);
        var normalizedDir = (new EReg('[/\\\\]+$', '')).replace(dir, ''); // strip trailing slashes
        var scanRoot = Path.join(projectRoot, normalizedDir);
        var files:Array<String> = [];
        var names:Array<String> = [];

        function walk(d:String):Promise<Nothing> {
            return new Promise((res, rej) -> {
                js.Syntax.code('{0}.readdir({1}, {2}, {3})', Fs, d, { withFileTypes: true },
                    (err, entries:Array<Dynamic>) -> {
                        if (err != null) { rej(err); return; }
                        var subs:Array<Promise<Nothing>> = [];
                        for (entry in entries) {
                            var fullPath = Path.join(d, entry.name);
                            if (entry.isDirectory()) {
                                var nm:String = entry.name;
                                if (!nm.startsWith('.') && nm != 'node_modules') subs.push(walk(fullPath));
                            } else if (entry.isFile()) {
                                var relativePath = Path.relative(scanRoot, fullPath).replace('\\', '/');
                                var m:Null<Array<String>> = js.Syntax.code('{0}.match({1})', relativePath, regex);
                                if (m == null) continue;
                                // Project-root-relative posix path (normalizedDir + relativePath).
                                files.push(js.Syntax.code('{0}.posix.join({1}, {2})', Path, normalizedDir, relativePath));
                                var name = nameTemplate;
                                for (i in 1...m.length) name = name.replace('$' + i, m[i] != null ? m[i] : '');
                                // No capture substitution happened → fall back to the file stem.
                                if (name == nameTemplate)
                                    name = js.Syntax.code('{0}.posix.parse({1}).name', Path, relativePath);
                                names.push(name);
                            }
                        }
                        Promise.all(subs).then(_ -> res(Nil)).catchError(e -> { rej(e); return null; });
                    });
            });
        }

        return walk(scanRoot).then(_ -> {
            // Sort by file path for a deterministic ordering, keeping names aligned.
            var pairs = [for (i in 0...files.length) { file: files[i], name: names[i] }];
            pairs.sort((a, b) -> (js.Syntax.code('{0}.localeCompare({1})', a.file, b.file):Int));
            return { files: [for (p in pairs) p.file], names: [for (p in pairs) p.name] };
        });
    }

    /**
     * Returns a list of all files in the directory. Doesn't include inner directories in non-recursive mode.
     */
    public static function listDirectoryFiles(dir:String, recursive:Bool = true):Promise<Array<String>> {
        return new Promise((res, rej) -> {
            var result = [];
            js.Syntax.code('{0}.readdir({1}, {2}, {3})', Fs, dir, { withFileTypes: true }, (err, files:Array<Dynamic>) -> {
                if (err != null) {
                    rej(err);
                } else {
                    var otherDirs = [];
                    for (file in files) {
                        var path = Path.join(dir, file.name);
                        if (file.isDirectory()) {
                            if (recursive) otherDirs.push(listDirectoryFiles(path, true));
                        } else {
                            result.push(path);
                        }
                    }
                    Promise.all(otherDirs).then((arr:Array<Array<String>>) -> {
                        for (a in arr) for (f in a) result.push(f);
                        res(result);
                    });
                }
            });
        });
    }

}

enum abstract Nothing(Dynamic) {

    var Nil = null;

}
