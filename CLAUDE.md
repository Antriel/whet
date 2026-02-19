# Overview

Whet is a NodeJS-based tool for managing project assets and tooling using a flexible "everything-is-an-asset" approach with configurable caching. It's written in Haxe and compiles to JavaScript (ES6 modules).

# Build Commands

- **Build the project**: `haxe build.hxml` (compiles Haxe to JavaScript, no output on success build)
- **Run a project**: `node bin/whet.js -p <project-file>` (default: `Project.mjs`)

The compiled output is `bin/whet.js` which serves as both the CLI entry point and importable library.

# Technology Stack

- **Language**: Haxe 4.3.4 (configured in `.haxerc`)
- **Target**: JavaScript ES6 modules (`-D js-es=6` in build.hxml)
- **Runtime**: Node.js
- **Key Libraries**:
  - `hxnodejs`: Node.js bindings for Haxe
  - `commander`: CLI argument parsing
  - `pino-pretty`: Logging
  - `minimatch`: Glob pattern matching
  - `mime`: MIME type detection

# Architecture

## Core Concepts

**Stones** are the fundamental building blocks. Each Stone represents a logical asset or functionality (e.g., a minified CSS file, a dev server). Stones can depend on other Stones, forming a dependency tree. All state is kept in a `config` object.

**Project** is the top-level container that holds Stones and commands. Projects are instantiated in `Project.mjs` files (or custom project files).

**Router** manages routing between Stones and file paths using glob patterns. Routes can filter, rename, and reorganize assets from Stones.

**Source** represents the generated output of a Stone. It contains one or more `SourceData` entries (each with a Buffer and SourceId).

**SourceHash** provides SHA-256 content hashing for caching and change detection. Hashes can be merged and combined to track dependencies.

**CacheManager** handles caching strategies (in-memory, file-based, or none) with configurable durability rules (by age, count, last use).

## Source Files Structure

- `src/whet/Whet.hx`: CLI entry point and command execution
- `src/whet/Project.hx`: Project container and command registration
- `src/whet/Stone.hx`: Abstract base class for all Stones
- `src/whet/route/Router.hx`: Asset routing and filtering
- `src/whet/Source.hx`: Generated asset data and file operations
- `src/whet/SourceHash.hx`: Content hashing utilities
- `src/whet/cache/`: Caching infrastructure (CacheManager, FileCache, MemoryCache)
- `src/whet/stones/`: Built-in Stone implementations (Files, JsonStone, RemoteFile, Server, Zip, HaxeBuild)
- `src/whet/magic/`: Type system abstractions (StoneId, MaybeArray, RoutePathType, MinimatchType)
- `externs/`: TypeScript definition conversions for Node.js libraries

## Key Design Patterns

1. **Everything-is-an-asset**: All project resources (files, builds, configurations) are treated as Stones
2. **Lazy generation**: Sources are only generated when needed and go through caching
3. **Hash-based caching**: Content hashing determines if regeneration is needed
4. **Lock acquisition**: Stones use `acquire()` to prevent parallel generation of the same resource
5. **Promise-based**: All async operations use Promises for consistency

## Path Conventions

- All paths use `/` as separator (cross-platform)
- Paths are relative to project root
- Directory paths end with `/` (e.g., `assets/` is a directory, `assets` is a file)
- `SourceId` is a type alias for relative paths

## Command Chaining

Commands can be chained with `+`:
```bash
node bin/whet.js -p Project.mjs command1 + command2
```

# Creating New Stones

Extend the abstract `Stone<T>` class:

1. Override `initConfig()` to set defaults
2. Override `addCommands()` to register CLI commands
3. Implement `generate(hash:SourceHash)` to create the asset
4. Optionally override `generateHash()` for optimization (to avoid generating sources just for hashing)

Stones automatically:
- Track dependencies via `config.dependencies`
- Handle caching based on `cacheStrategy`
- Merge dependency hashes into their own hash
- Lock during generation to prevent race conditions

# Testing

- **Run tests**: `node --test "test/**/*.test.mjs"`
- **Framework**: Node.js built-in test runner (`node:test`) with `node:assert/strict`
- **Test files**: `test/*.test.mjs` — each file covers a specific area (cache, stone, router, etc.)
- **Helpers** (`test/helpers/`):
  - `test-env.mjs`: `createTestProject(name)` creates a temp dir + Project; returns `{ project, rootDir, write, read, exists, cleanup }`
  - `mock-stone.mjs`: `MockStone` extends Stone with configurable `outputs`, `hashKey`, `delayMs`; tracks `generateCount`
- Tests are written in JS (not Haxe) against the compiled `bin/whet.js` output — build before testing
- Haxe private methods (like `generate`, `generateHash`, `list`, `generatePartial`) are overridable from JS subclasses

# Working with Haxe

- **Type system**: Haxe is statically typed; use proper type annotations
- **Abstracts**: Many types like `SourceId`, `StoneId`, `MaybeArray` are abstract types with compile-time transformations
- **Macros**: Build-time code generation used for versioning and post-processing (`whet.Macros`)
- **@:expose metadata**: Makes classes available to JavaScript (see build.hxml for `whet.stones` exposure)
- **JS interop**: Use `js.Syntax.code()` for raw JavaScript when needed
- **Type unification**: `cast` is used for Promise type unification

# Bash Tips

**CRITICAL: Backticks in beans commands** — When updating bean body content that contains backticks (code snippets, template literals, etc.), you MUST use a heredoc with a QUOTED delimiter to prevent bash command substitution:
  ```bash
  # WRONG - backticks will be interpreted by bash
  beans update <id> --body-append "text with \`code\`"
  echo "text with \`code\`" | beans update <id> --body-append -

  # CORRECT - heredoc with quoted delimiter (<<'EOF' not <<EOF)
  beans update <id> --body-append "$(cat <<'EOF'
  text with `code` and `backticks`
  EOF
  )"
  ```
