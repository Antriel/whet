package whet.magic;

import minimatch.Minimatch;

typedef MinimatchType = EitherType<Minimatch, String>;

function makeMinimatch(src:MinimatchType):Minimatch {
    return if (src is String) new Minimatch(src)
    else if (js.Syntax.code('{0} instanceof {1}', src, Minimatch)) src
    else throw new js.lib.Error("Expected a string or Minimatch object.");
}
