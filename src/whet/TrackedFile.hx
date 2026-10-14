package whet;

import js.node.Buffer;
import js.node.Fs;
import js.node.Path;

/**
 * A file whet both reads and writes (an authored input, e.g. a `JsonDb` or `ConfigStore` file).
 * Records the disk state of the last read/write, so whet can tell when someone else (another
 * process, an agent, `git checkout`, a hand edit) changed it, and refuses to overwrite such a change
 * unless forced.
 */
class TrackedFile {

    /** `code` of the error `write` rejects with when the file changed on disk since last read/write. */
    public static inline final CONFLICT = 'WHET_FILE_CONFLICT';

    /** File system path (as passed to `Fs`). */
    public final path:String;

    /** Disk state at the last read/write; null when unknown (never read, or forgotten). */
    var state:Null<DiskState> = null;

    public function new(path:String) {
        this.path = path;
    }

    /**
     * Read the file and record its disk state. Resolves with the content, or null if the file
     * doesn't exist (recorded as absent, so a file created later counts as a change).
     */
    public function read():Promise<Null<String>> {
        // Stat before reading: a write in between leaves an older mtime with newer content, which
        // `changed` then resolves by content hash, instead of a newer mtime hiding newer content.
        return stat().then(stats -> {
            if (stats == null) {
                state = { exists: false, mtimeMs: 0, size: 0, hash: null };
                return Promise.resolve(null);
            }
            return new Promise((res, rej) -> Fs.readFile(path, (err, buf:Buffer) -> {
                if (err != null) {
                    if ((err:Dynamic).code == 'ENOENT') {
                        state = { exists: false, mtimeMs: 0, size: 0, hash: null };
                        res(null);
                    } else rej(err);
                    return;
                }
                state = { exists: true, mtimeMs: stats.mtimeMs, size: stats.size, hash: hashOf(buf) };
                res(buf.toString('utf-8'));
            }));
        });
    }

    /**
     * Whether the file on disk differs from the recorded state. Cheap stat compare; only when mtime
     * moved but size didn't is the content hashed (a matching hash just refreshes the recorded
     * mtime). With no recorded state, an existing file counts as changed (its content is unknown).
     */
    public function changed():Promise<Bool> {
        return stat().then(stats -> {
            if (stats == null) return Promise.resolve(state == null ? false : state.exists);
            if (state == null || !state.exists || stats.size != state.size) return Promise.resolve(true);
            if (stats.mtimeMs == state.mtimeMs) return Promise.resolve(false);
            return new Promise((res, rej) -> Fs.readFile(path, (err, buf:Buffer) -> {
                if (err != null) {
                    if ((err:Dynamic).code == 'ENOENT') res(true) else rej(err);
                    return;
                }
                if (hashOf(buf) != state.hash) res(true) else {
                    state.mtimeMs = stats.mtimeMs;
                    res(false);
                }
            }));
        });
    }

    /**
     * Write `content` and record the new state. Unless `force`, rejects with a `CONFLICT` error if
     * the file changed on disk since the last read/write — except when the disk already holds exactly
     * `content` (a checkout back to the same bytes, another writer making the same edit) — and skips
     * the write when the bytes already match. Writes via a temp file + rename, so readers never see a
     * partial file. Resolves true if bytes were written.
     */
    public function write(content:String, force:Bool = false):Promise<Bool> {
        var buf = Buffer.from(content, 'utf-8');
        var hash = hashOf(buf);
        var check:Promise<Bool> = force ? Promise.resolve(false) : changed();
        return check.then(changed -> {
            if (changed) return adoptIfSame(hash).then(same -> same ? false : throw conflictError(path));
            if (!force && state != null && state.exists && state.hash == hash) return Promise.resolve(false);
            var tmp = path + '.' + js.Node.process.pid + '-' + Std.string(Std.random(0x7fffffff)) + '.tmp';
            return Utils.ensureDirExist(Path.dirname(path)).then(_ -> new Promise((res, rej) -> {
                Fs.writeFile(tmp, buf, err -> {
                    if (err != null) return rej(err);
                    Fs.rename(tmp, path, err -> {
                        if (err != null) {
                            Fs.unlink(tmp, _ -> rej(err));
                            return;
                        }
                        stat().then(stats -> {
                            state = { exists: true, mtimeMs: stats.mtimeMs, size: stats.size, hash: hash };
                            res(true);
                        }, rej);
                    });
                });
            }));
        });
    }

    /** If the disk holds content hashing to `hash`, record that state and resolve true. */
    function adoptIfSame(hash:String):Promise<Bool> {
        return stat().then(stats -> {
            if (stats == null) return Promise.resolve(false);
            return new Promise((res, rej) -> Fs.readFile(path, (err, buf:Buffer) -> {
                if (err != null) {
                    if ((err:Dynamic).code == 'ENOENT') res(false) else rej(err);
                    return;
                }
                if (hashOf(buf) != hash) return res(false);
                state = { exists: true, mtimeMs: stats.mtimeMs, size: stats.size, hash: hash };
                res(true);
            }));
        });
    }

    /** Drop the recorded state, so the next `changed` re-checks against the real disk content. */
    public function forget():Void {
        state = null;
    }

    function stat():Promise<Null<StatInfo>> {
        return new Promise((res, rej) -> Fs.stat(path, (err, stats) -> {
            if (err != null) {
                if ((err:Dynamic).code == 'ENOENT') res(null) else rej(err);
            } else res(cast stats);
        }));
    }

    static inline function hashOf(buf:Buffer):String return SourceHash.fromBytes(buf).toHex();

    /** A `CONFLICT` error for `path`; `detail` replaces the default description. */
    public static function conflictError(path:String, ?detail:String):js.lib.Error {
        var err = new js.lib.Error((detail != null ? detail : 'File changed on disk since it was last read.')
            + ' ($path) Reload it, or save with force to overwrite.');
        (cast err).code = CONFLICT;
        (cast err).path = path;
        return err;
    }

}

private typedef DiskState = {
    var exists:Bool;
    var mtimeMs:Float;
    var size:Float;
    var hash:Null<String>;
}

private typedef StatInfo = {
    var mtimeMs:Float;
    var size:Float;
}
