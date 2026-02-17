package whet;

import whet.Log.LogLevel;

var program = new commander.Command('whet');

function main() {
    // Only run CLI when executed directly, not when imported as a library.
    final entryUrl = js.node.Url.pathToFileURL(js.Node.process.argv[1] ?? "").href;
    final thisUrl:String = js.Syntax.code("new URL('../whet.js',import.meta.url).href");
    if (entryUrl != thisUrl) return;

    program.enablePositionalOptions().passThroughOptions()
        .description('Project tooling.')
        .usage('[options] [command] [+ [command]...]')
        .version(Macros.getVersion(), '-v, --version')
        .allowUnknownOption(true)
        .showSuggestionAfterError(true)
        .option('-p, --project <file>', 'project to run', 'Project.mjs')
        .option('-l, --log-level <level>', 'log level, a string/number', 'info')
        .option('--no-pretty', 'disable pretty logging')
        .exitOverride();

    try {
        program.parse();
    } catch (err) {
        if (err.native is commander.CommanderError && (err.native:Dynamic).code == 'commander.version') js.Node.process.exit();
        else throw err;
    }
    final options = program.opts();
    if (options.logLevel != null) { // Handle logLevel immediately.
        var n = Std.parseInt(options.logLevel);
        if (n == null) n = LogLevel.fromString(options.logLevel);
        if (n == null) program.error('Invalid value for --log-level');
        else Log.logLevel = n;
    }
    if (options.pretty) Log.stream = PinoPretty.default_();

    js.Node.setImmediate(init, options); // Init next tick, in case the project file was executed directly.
}

private function init(options:Dynamic) {
    if (Project.projects.length > 0) { // Project already loaded.
        initProjects();
    } else { // Load project.
        Log.info('Loading project.', { file: options.project });
        var path = js.node.Url.pathToFileURL(options.project).href;
        Log.debug('Resolved project path.', { path: path });

        var projectProm:Promise<js.node.Module> = js.Syntax.code('import({0})', path);
        projectProm.then(module -> {
            Log.trace('Project module imported.');
            initProjects();
        }).catchError(e -> {
            Log.error("Error loading project.", { error: e });
            if (e is js.lib.Error) Log.error((e:js.lib.Error).stack);
            try {
                program.help();
            } catch (e) { }
        });
    }
}

private function initProjects() {
    Log.trace('Parsing remaining arguments.', { args: program.args });
    for (project in Project.projects) {
        for (opt in project.options) program.addOption(opt);
    }
    program.allowUnknownOption(false);

    var commands = getCommands(program.args);
    var initProm = if (commands.length > 0) {
        var res = program.parseOptions(commands[0]);
        commands[0] = res.operands.concat(res.unknown);

        var promises:Array<Promise<Any>> = [];
        for (p in Project.projects) if (p.onInit != null) {
            Log.trace('Initializing project.', { project: p.id });
            p.config = program.opts();
            var prom = p.onInit(p.config);
            if (prom != null) promises.push(prom);
        }
        Promise.all(promises);
    } else Promise.resolve();
    function nextCommand() {
        if (commands.length == 0) return;
        final c = commands.shift();
        Log.trace('Executing command.', { commandArgs: c });
        program.parseAsync(c, { from: 'user' }).then(_ -> nextCommand())
            .catchError(err -> {
                if (err is commander.CommanderError && err.code == 'commander.help')
                    return;
                Log.error("Error while executing command.", { error: err });
            });
    }
    initProm.then(_ -> nextCommand());
}

function executeCommand(cmd:Array<String>) {
    Log.trace('Executing command.', { command: cmd });
    return program.parseAsync(cmd, { from: 'user' });
}

private function getCommands(args:Array<String>):Array<Array<String>> {
    var commands = [];
    var from = 0;
    var to;
    do {
        to = args.indexOf('+', from);
        commands.push(to < 0 ? args.slice(from) : args.slice(from, to));
        from = to + 1;
    } while (to >= 0);
    return commands;
}
