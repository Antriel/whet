# Whet

A NodeJS-based tool for managing things every project needs, such as configuration, build scripts, assets, etc., using a flexible everything-is-an-asset approach, with configurable caching.

## Project Files

Project files define a project, its [stones](#Stones). Their content defines what [commands](#Commands) are available.

## Stones

Stones (named after _whetstone_) are individual building blocks of a project.

They represent a single logical asset (can be multiple files) or functionality (e.g. a dev web server). Stones can use other stones (via routes), to achieve their objective, forming a dependency tree. E.g. a CSS file could be made by minifying a file generated from SCSS source, and each step could be individually cached.

### Stones Configuration

Stones try to keep all their state in a `config` object. Each stone requires it to be supplied. The `config` object should be designed for scripting, i.e. allow dynamic types as long as they make sense.

Reading and applying the configuration should be limited to generating resources/hashes from the stone. Invalid configuration therefore won't crash the project initialization until it's being used. This is just a guideline and not a requirement, and stones might validate the configuration immediately where it makes sense.

<!-- TODO: Implement, and then mention `project.getHash()` as a way to verify the whole project. -->

Some stones might provide helper methods to modify the configuration after it was passed in. Such methods might modify the `config` object, e.g. turning a single entry into array of them.

### Hashes

...

### Commands

...

## Routers

...

## Core Concepts

Project files should have no side effects, unless some of their commands are executed. They only process the active configuration, initializing the available commands.

<!-- TODO: document configuration handlers -->

All file paths should use `/` as directory separator, regardless of platform.

Paths should always be relative, and are considered relative to root project directory, or relative to root of the Router/Stone used. For getting sources from Stones/Routers [minimatch](https://github.com/isaacs/minimatch/) is used.

Path that is a directory ends with a `/`, otherwise it's considered a file. That means:

- `assets/` is a **directory** called `assets`.
- `assets` is a **file** called `assets`.
