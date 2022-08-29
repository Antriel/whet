package whet.extern;

@:jsRequire("minimatch") extern class Minimatch {

    @:native("Minimatch") public static var cls:Class<Minimatch>;

    public static inline function makeNew(pattern:String, ?options:IOptions):Minimatch {
        return js.Syntax.construct(cls, pattern, options);
    }

    /**
        The original pattern the minimatch object represents.
    **/
    var pattern:String;

    /**
        The options supplied to the constructor.
    **/
    var options:IOptions;

    /**
        A 2-dimensional array of regexp or string expressions. Each row in the array corresponds
        to a brace-expanded pattern. Each item in the row corresponds to a single path-part. For
        example, the pattern `{a,b/c}/d` would expand to a set of patterns like:

        ```
           [ [ a, d ]
           , [ b, c, d ] ]
        ```

        If a portion of the pattern doesn't have any "magic" in it (that is, it's something like `"foo"``
        rather than `fo*o?`), then it will be left as a string rather than converted to a regular expression.
    **/
    var set:Array<Array<ts.AnyOf2<String, js.lib.RegExp>>>;

    /**
        Created by the `makeRe` method. A single regular expression expressing the entire pattern. This is
        useful in cases where you wish to use the pattern somewhat like `fnmatch(3)` with `FNM_PATH` enabled.
    **/
    var regexp:Null<ts.AnyOf2<Bool, js.lib.RegExp>>;

    /**
        True if the pattern is negated.
    **/
    var negate:Bool;

    /**
        True if the pattern is a comment.
    **/
    var comment:Bool;

    /**
        True if the pattern is `""`.
    **/
    var empty:Bool;

    /**
        True if windows path delimiters shouldn't be interpreted as escape characters.
    **/
    var windowsPathsNoEscape:Bool;

    /**
        True if partial paths should be compared to a pattern.
    **/
    var partial:Bool;

    /**
        Generate the `regexp` member if necessary, and return it. Will return `false` if the pattern is invalid.
    **/
    function makeRe():ts.AnyOf2<Bool, js.lib.RegExp>;

    function match(fname:String, ?partial:Bool):Bool;

    /**
        Take a `/`-split filename, and match it against a single row in the `regExpSet`.
        This method is mainly for internal use, but is exposed so that it can be used
        by a glob-walker that needs to avoid excessive filesystem calls.
    **/
    function matchOne(file:String, pattern:haxe.ds.ReadOnlyArray<String>, partial:Bool):Bool;

    function debug():Void;
    function make():Void;
    function parseNegate():Void;
    function braceExpand():Array<String>;
    function parse(pattern:String, ?isSub:Bool):Dynamic;
    static var prototype:Minimatch;
    static function defaults(defaultOptions:IOptions):{
        var prototype:Minimatch;
        function defaults(defaultOptions:IOptions):Dynamic;
    };

}

typedef IOptions = {

    /**
        Dump a ton of stuff to stderr.
    **/
    @:optional
    var debug:Bool;

    /**
        Do not expand `{a,b}` and `{1..3}` brace sets.
    **/
    @:optional
    var nobrace:Bool;

    /**
        Disable `**` matching against multiple folder names.
    **/
    @:optional
    var noglobstar:Bool;

    /**
        Allow patterns to match filenames starting with a period,
        even if the pattern does not explicitly have a period in that spot.

        Note that by default, `'a/**' + '/b'` will **not** match `a/.d/b`, unless `dot` is set.
    **/
    @:optional
    var dot:Bool;

    /**
        Disable "extglob" style patterns like `+(a|b)`.
    **/
    @:optional
    var noext:Bool;

    /**
        Perform a case-insensitive match.
    **/
    @:optional
    var nocase:Bool;

    /**
        When a match is not found by `minimatch.match`,
        return a list containing the pattern itself if this option is set.
        Otherwise, an empty list is returned if there are no matches.
    **/
    @:optional
    var nonull:Bool;

    /**
        If set, then patterns without slashes will be matched
        against the basename of the path if it contains slashes. For example,
        `a?b` would match the path `/xyz/123/acb`, but not `/xyz/acb/123`.
    **/
    @:optional
    var matchBase:Bool;

    /**
        Suppress the behavior of treating `#` at the start of a pattern as a comment.
    **/
    @:optional
    var nocomment:Bool;

    /**
        Suppress the behavior of treating a leading `!` character as negation.
    **/
    @:optional
    var nonegate:Bool;

    /**
        Returns from negate expressions the same as if they were not negated.
        (Ie, true on a hit, false on a miss.)
    **/
    @:optional
    var flipNegate:Bool;

    /**
        Compare a partial path to a pattern.  As long as the parts of the path that
        are present are not contradicted by the pattern, it will be treated as a
        match. This is useful in applications where you're walking through a
        folder structure, and don't yet have the full path, but want to ensure that
        you do not walk down paths that can never be a match.
    **/
    @:optional
    var partial:Bool;

    /**
        Use `\\` as a path separator _only_, and _never_ as an escape
        character. If set, all `\\` characters are replaced with `/` in
        the pattern. Note that this makes it **impossible** to match
        against paths containing literal glob pattern characters, but
        allows matching with patterns constructed using `path.join()` and
        `path.resolve()` on Windows platforms, mimicking the (buggy!)
        behavior of earlier versions on Windows. Please use with
        caution, and be mindful of the caveat about Windows paths

        For legacy reasons, this is also set if
        `options.allowWindowsEscape` is set to the exact value `false`.
    **/
    @:optional
    var windowsPathsNoEscape:Bool;

};
