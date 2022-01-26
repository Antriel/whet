package whet.magic;

typedef MaybeArray<T> = EitherType<T, Array<T>>;

function makeArray<T>(maybe:MaybeArray<T>):Array<T> {
    return if (maybe is Array) maybe else if (maybe == null) [] else [maybe];
}
