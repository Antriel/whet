package whet.stones;

import js.node.Fs;
import whet.Stone.OutputFilter;

/**
 * A JSON-file-backed data stone. Holds parsed JSON in `data`, generates it back as a pretty-printed
 * file (the stone id doubles as the output filename), and can `load`/`flush` against a path on disk.
 *
 * Promoted from AudioDb's private `JsonDb`; backs StoneStore and any data-driven factory.
 */
class JsonDb extends Stone<JsonDbConfig> {

    /** Parsed JSON contents — whatever `JSON.parse` yields (array or object). */
    public var data:Dynamic;

    override function generate(hash:SourceHash):Promise<Array<SourceData>> {
        return Promise.resolve([SourceData.fromString(this.id, haxe.Json.stringify(data, null, '  '))]);
    }

    override function list():Promise<Null<Array<SourceId>>>
        return Promise.resolve([(this.id:SourceId)]);

    override public function getOutputFilter():Null<OutputFilter>
        return { extensions: ['json'] };

    /**
     * Load JSON from `path` (project-relative). Missing file → warn and fall back to
     * `config.defaultData ?? []`. Then bind this stone's absolute cache path to `path` (so `flush`
     * writes there) without generating. Resolves with `this`.
     */
    @:keep public function load(path:String):Promise<JsonDb> {
        return new Promise((res, rej) -> {
            Fs.readFile(cwdPath(path), 'utf-8', (err, content) -> {
                if (err != null) {
                    if ((err:Dynamic).code == 'ENOENT') {
                        Log.warn('DB file does not exist, using default data.', { path: path });
                        data = config.defaultData != null ? config.defaultData : [];
                    } else {
                        rej(err);
                        return;
                    }
                } else {
                    data = haxe.Json.parse(content);
                }
                setAbsolutePath(path, false).then(_ -> res(this), rej);
            });
        });
    }

    /**
     * Persist current `data` to the bound absolute path. The `AbsolutePath(_, LimitCountByAge(1))`
     * strategy from `setAbsolutePath` (via `load`) only rewrites the file when the hash changed.
     */
    @:keep public function flush():Promise<Source> {
        return getSource();
    }

    /**
     * Reference `configSchema()` (the convention `StoneRegistry` picks up): a shallow, permissive
     * JSON-Schema fragment describing this stone's editable config. `defaultData` is free-form JSON,
     * so it is described only as "present" without a shape. Intentionally omits
     * `additionalProperties:false` (permissive-by-default convention).
     */
    @:keep public static function configSchema():Dynamic {
        return {
            type: "object",
            properties: {
                defaultData: { description: "Fallback contents when the loaded file is missing." }
            }
        };
    }

}

typedef JsonDbConfig = StoneConfig & {

    /** Fallback contents when `load`'s target file is missing. Defaults to `[]`. */
    var ?defaultData:Dynamic;

}
