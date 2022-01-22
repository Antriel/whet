package whet.magic;

typedef StoneIdType = EitherType<String, EitherType<Class<AnyStone>, AnyStone>>;

function makeStoneId(id:StoneIdType):String {
    if (id is String) {
        return id;
    } else if (id is Class) {
        return makeStoneIdFromClass(id);
    } else if (id is AnyStone) {
        return makeStoneIdFromClass(Type.getClass(id));
    } else throw new js.lib.Error("Unsupported type for StoneId.");
}

private function makeStoneIdFromClass(c:Class<AnyStone>):String {
    return Type.getClassName(c).split('.').pop();
}
