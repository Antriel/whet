package whet;

/**
 * Hand-written (not dts2hx-generated) extern for the bit of `pino-pretty` Whet uses.
 * dts2hx emits `customPrettifiers` as `DynamicAccess<Prettifier> & {...}`, which Haxe
 * can't type ("Can only extend structures"), so the generated externs don't compile.
 */
@:jsRequire("pino-pretty") extern class PinoPretty {

    @:selfCall static function call(?options:PinoPrettyOptions):Dynamic;

}

/** Subset of pino-pretty's `PrettyOptions`; add fields as needed. */
typedef PinoPrettyOptions = {

    /** File descriptor or path to write to (e.g. `2` for stderr). */
    @:optional var destination:haxe.extern.EitherType<Int, String>;
    @:optional var colorize:Bool;

}
