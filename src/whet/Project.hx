package whet;

@:expose
class Project {

    public final name:String;
    public final id:String;
    public final description:String;
    public final rootDir:SourceId;
    public final cache:CacheManager = null;

    @:allow(whet) private static final projects:Array<Project> = [];

    public function new(config:ProjectConfig) {
        Log.trace('Instantiating new Project.');
        if (config == null || config.name == null) throw new js.lib.Error("Must supply config and a name.");
        name = config.name;
        if (config.id == null) id = StringTools.replace(config.name, ' ', '-').toLowerCase();
        else id = config.id;
        description = config.description;

        if (config.rootDir == null) {
            final oldValue = js.Syntax.code('Error').prepareStackTrace;
            js.Syntax.code('Error').prepareStackTrace = (_, stack) -> stack;
            // 0 us, 1 genes.Register, 2 us again, 3 is the caller.
            var file:String = untyped new js.lib.Error().stack[3].getFileName();
            js.Syntax.code('Error').prepareStackTrace = oldValue;
            file = StringTools.replace(file, 'file:///', '');
            rootDir = (js.node.Path.relative(js.Node.process.cwd(), file):SourceId).dir;
            // TODO write tests for this.
        } else rootDir = config.rootDir;
        cache = config.cache == null ? new CacheManager(this) : config.cache;
        // commands = new Map();
        // commandsMeta = [];
        projects.push(this);
        Log.info('New project created.', { project: this, projectCount: projects.length });
    }

    public function toString() return '$name@$rootDir';

}

typedef ProjectConfig = {

    public var name:String;
    public var ?id:String;
    public var ?description:String;
    public var ?cache:CacheManager;
    public var ?rootDir:String;

}
