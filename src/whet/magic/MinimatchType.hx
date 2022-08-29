package whet.magic;

import whet.extern.Minimatch;

typedef MinimatchType = EitherType<Minimatch, String>;

function makeMinimatch(src:MinimatchType):Minimatch {
    return if (src is String) Minimatch.makeNew(src)
    else if (js.Syntax.code('{0} instanceof {1}', src, Minimatch.cls)) src
    else throw new js.lib.Error("Expected a string or Minimatch object.");
}
