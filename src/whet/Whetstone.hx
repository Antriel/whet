package whet;

import haxe.DynamicAccess;
import haxe.rtti.Meta;

class Whetstone {

    var project:WhetProject;

    public function new(project:WhetProject) {
        this.project = project;
        if (project.stones.exists(this)) Whet.error('Duplicate whetstone "${(this:WhetstoneID)}".');
        project.stones.set(this, this);
        var meta:DynamicAccess<Dynamic> = Meta.getFields(Type.getClass(this));
        for (name => val in meta) {
            if (Reflect.hasField(val, 'command')) {
                var justClass = ((this:WhetstoneID):String).split('.').pop();
                project.commands.set('$justClass.$name', Reflect.field(this, name));
                if (!project.commands.exists(name)) { // add short alias if none yet exists
                    project.commands.set(name, function(arg) Reflect.callMethod(this, Reflect.field(this, name), [arg]));
                }
            }
        }
    }

    #if tink_io
    public function getSource<T>(id:SourceId):tink.io.Source<T> {
        throw "Not implemented";
    }
    #end

}

abstract WhetstoneID(String) from String to String {

    @:from
    public static inline function fromClass(v:Class<Whetstone>):WhetstoneID
        return Type.getClassName(v);

    @:from
    public static inline function fromInstance(v:Whetstone):WhetstoneID
        return fromClass(Type.getClass(v));
}
