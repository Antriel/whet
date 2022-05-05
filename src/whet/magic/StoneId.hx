package whet.magic;

typedef StoneIdType = EitherType<String, EitherType<Class<AnyStone>, AnyStone>>;

function makeStoneId(id:StoneIdType):String {
    if (id is String) {
        return id;
    } else if (id is Class) {
        return makeStoneIdFromClass(id);
    } else if (id is AnyStone) {
        return js.Syntax.code('{0}.constructor.name', id);
    } else throw new js.lib.Error("Unsupported type for StoneId.");
}

private function makeStoneIdFromClass(c:Class<AnyStone>):String {
    return Type.getClassName(c).split('.').pop();
}

function getTypeName(stone:AnyStone) {
    final name = Type.getClassName(Type.getClass(stone));
    return if (name != "whet.Stone") name; // If it's not Haxe type, just return class name.
    else js.Syntax.code('{0}.constructor.name', stone);
}
