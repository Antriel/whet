package whet;

import js.node.Fs;
import whet.Log.LogLevel;

var program = new commander.Command('whet');

/** 
 * True when the invocation requested top-level help (`whet --help` / `-h`), as
 * opposed to a subcommand help (`whet greet --help`). Set after the first parse.
 */
private var topLevelHelp = false;

function main() {
    // Only run CLI when executed directly, not when imported as a library.
    // Use realpathSync to resolve symlinks (e.g. from npm link) before comparing.
    final argv1 = js.Node.process.argv[1] ?? "";
    final realArgv1:String = try Fs.realpathSync(argv1) catch(e:Dynamic) argv1;
    final entryUrl = js.node.Url.pathToFileURL(realArgv1).href;
    final thisUrl:String = js.Syntax.code("new URL('../whet.js',import.meta.url).href");
    if (entryUrl != thisUrl) return;

    program.enablePositionalOptions().passThroughOptions()
        .description('Project tooling.')
        .usage('[options] [command] [+ [command]...]')
        .version(Macros.getVersion(), '-v, --version')
        .allowUnknownOption(true)
        .allowExcessArguments(true)
        .showSuggestionAfterError(true)
        // Disable the built-in help option for this first parse: the project isn't
        // loaded yet, so its commands aren't known. With allowUnknownOption it passes
        // through into `program.args` and is handled in the second pass (initProjects),
        // exactly like the `help` command — so `whet --help` shows project commands too.
        .helpOption(false)
        .option('-p, --project <file>', 'project to run', 'Project.mjs')
        .addOption(new commander.Option('-l, --log-level <level>', 'log level, a string/number').default_('info').env('WHET_LOG_LEVEL'))
        .option('--no-pretty', 'disable pretty logging')
        .option('-q, --quiet', 'quiet output: warn level + no color (the default when stdout is not a TTY)')
        .option('--profile <format>', 'enable profiling, export to whet-profile.json on exit (format: json or trace, default: json)')
        .exitOverride();

    try {
        program.parse();
    } catch (err) {
        if (err.native is commander.CommanderError
            && ((err.native:Dynamic).code == 'commander.version'
                || (err.native:Dynamic).code == 'commander.helpDisplayed')) js.Node.process.exit();
        else throw err;
    }
    // `--help`/`-h` now passes through (helpOption disabled above). Detect whether it
    // was a top-level request (first command segment leads with a help flag) vs a
    // subcommand one (`whet greet --help`), which is handled by the subcommand itself.
    final firstSegment = getCommands(program.args)[0];
    topLevelHelp = firstSegment.length > 0 && (firstSegment[0] == '--help' || firstSegment[0] == '-h');

    final options = program.opts();
    if (options.logLevel != null) { // Validate & apply --log-level / WHET_LOG_LEVEL.
        var n = Std.parseInt(options.logLevel);
        if (n == null) n = LogLevel.fromString(options.logLevel);
        if (n == null) program.error('Invalid value for --log-level');
        else Log.logLevel = n;
    }
    // Auto-quiet when stdout is not a TTY (piped/scripted/agent use): default to warn +
    // no color so machine consumers get cheap, clean output. Explicit choices always win —
    // -l/--log-level (incl. WHET_LOG_LEVEL) sets the level, --no-pretty disables color; and
    // -q/--quiet forces quiet regardless. Logs go to stderr (see Log.hx) so stdout results
    // stay clean either way; pretty output is routed to stderr too (destination: 2).
    final nonTty = (cast js.Node.process.stdout).isTTY != true;
    final levelSource:String = cast program.getOptionValueSource('logLevel');
    final prettySource:String = cast program.getOptionValueSource('pretty');
    if (options.quiet || (nonTty && levelSource == 'default')) Log.logLevel = Warn;
    final usePretty = if (options.quiet) false
        else if (prettySource != 'default') options.pretty // --no-pretty explicitly set
        else !nonTty; // default: color in a terminal, plain when piped
    if (usePretty) Log.stream = PinoPretty.call({ destination: 2 });

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
            // If all the user asked for was top-level help, the project failing to load
            // shouldn't bury it under an error — just print the (global) help cleanly.
            if (!topLevelHelp) {
                Log.error("Error loading project.", { error: e });
                if (e is js.lib.Error) Log.error((e:js.lib.Error).stack);
            }
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
    // Re-enable the help option now that the project (and its commands) is loaded, so a
    // passed-through top-level `--help`/`-h` renders the full help in the command loop below.
    program.helpOption('-h, --help', 'display help for command');

    var schemaCmd = new commander.Command('schema');
    schemaCmd.description('Export project schema as JSON.');
    schemaCmd.action(cast outputSchema);
    program.addCommand(schemaCmd);

    var commands = getCommands(program.args);
    var initProm = if (commands.length > 0) {
        var res = program.parseOptions(commands[0]);
        commands[0] = res.operands.concat(res.unknown);

        // Enable profiling on all projects if --profile flag is set.
        var profileFormat:Dynamic = program.opts().profile;
        if (profileFormat != null) {
            var format:String = if (profileFormat == true) "json" else profileFormat;
            for (p in Project.projects) p.enableProfiling();
            var onExit = () -> {
                for (p in Project.projects) {
                    if (p.profiler != null) {
                        var data = p.profiler.exportProfile(format);
                        var json:String = haxe.Json.stringify(data, null, '  ');
                        js.node.Fs.writeFileSync('whet-profile.json', json);
                    }
                }
            };
            js.Node.process.on('exit', onExit);
        }

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
                // 'commander.help' = the `help` command; 'commander.helpDisplayed' = the
                // `--help`/`-h` option. Both just printed help — not errors.
                if (err is commander.CommanderError
                    && (err.code == 'commander.help' || err.code == 'commander.helpDisplayed'))
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

private function outputSchema():Void {
    Log.logLevel = 100;
    var excludeCommands = ['help', 'schema'];
    var schema:Dynamic = {
        projects: [for (p in Project.projects) ({
            name:p.name, id:p.id, description:p.description, options:[for (opt in p.options)
                serializeOption(opt)],
        }:Dynamic)],
        commands: [for (cmd in (cast program.commands:Array<commander.Command>))
            if (!excludeCommands.contains(cmd.name())) serializeCommand(cmd)
        ],
    };
    js.Node.process.stdout.write(haxe.Json.stringify(schema, null, '  ') + '\n');
}

private function serializeOption(opt:commander.Option):Dynamic {
    return {
        name: opt.name(),
        attributeName: opt.attributeName(),
        flags: opt.flags,
        description: opt.description,
        choices: opt.argChoices,
        defaultValue: opt.defaultValue,
        required: opt.required,
        mandatory: opt.mandatory,
        boolean: opt.isBoolean(),
        hidden: opt.hidden,
    };
}

private function serializeArgument(arg:commander.Argument):Dynamic {
    return {
        name: arg.name(),
        description: arg.description,
        choices: arg.argChoices,
        defaultValue: arg.defaultValue,
        required: arg.required,
        variadic: arg.variadic,
    };
}

private function serializeCommand(cmd:commander.Command):Dynamic {
    return {
        name: cmd.name(),
        description: cmd.description(),
        aliases: cmd.aliases(),
        options: [for (opt in (cast cmd.options:Array<commander.Option>)) serializeOption(opt)],
        arguments: [for (arg in (cast cmd.registeredArguments:Array<commander.Argument>)) serializeArgument(arg)],
    };
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
