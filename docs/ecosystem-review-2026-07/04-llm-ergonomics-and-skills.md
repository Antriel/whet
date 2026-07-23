# LLM Ergonomics & Skills Update

Goal: make agents fast and cheap at discovering and driving Whet projects.

## CLI grammar (the reference the skills now teach)

Whet uses Commander with `enablePositionalOptions().passThroughOptions()`, and parses
in two passes (own options first, project loaded, then command segments):

- **Project options go before the first command.** Anything after a command name is
  passed through *to that command*; unknown options there are errors.
  - `npx whet --platform dev build` ✅
  - `npx whet build --platform dev` ❌ — `build` doesn't declare `--platform`.
- **`+` chains commands**: `npx whet -b publish build + export-zip`. `onInit` runs
  once (with the project options), then segments execute sequentially.
- **Project options are only parsed from the first `+` segment** (`Whet.hx`
  `initProjects` calls `parseOptions(commands[0])`). Options in later segments are
  handed to that segment's command and typically error. One build mode per invocation.
- `whet schema` separates the scopes: `projects[].options` (before the command) vs
  `commands[].options`/`arguments` (after the command name).
- Command-name collisions: the later stone-registered command gets the
  `stoneId.name` form; the first keeps the plain name plus a `stoneId.name` alias.

## What changed in the two skills

`~/.claude/skills/whet/SKILL.md`:

- Added the **CLI grammar** section above (ordering was the missing piece — agents
  were guessing `build --platform dev` and hitting unknown-option errors).
- Added **`stone-cat`** to the introspection verbs (it was missing entirely) with its
  binary-refusal / `--base64` / `-n` behavior.
- Rewrote the outdated **"When there's no CLI command"** section: the introspection
  verbs come from ScryStone which is wired into practically every project
  (`ScryDevTools` is part of the standard layout), so the skill now presents them as
  the norm, with the HTTP/WS server surface as the live-server alternative.

`~/.claude/skills/whet-pipeline/SKILL.md`:

- Added a **StoneFactory** section (the AudioDb pattern: `sync(data, keyFn)`,
  `createEntry`/`updateEntry`/`addBaseRoutes`, stable per-entry ids, Router-compatible).
- Added the **explicit-id rule**: any stone participating in a ConfigStore (or
  otherwise persistently keyed) needs an explicit `id` — implicit ids auto-suffix by
  instantiation order and silently re-key persisted config.
- Noted `addCommand(name, stone)` alias-on-collision behavior.

## Further ideas (not yet implemented)

Ordered by value-per-effort:

1. **`whet schema --stones`** — include `describeStones()` (id, class, cacheStrategy,
   origin once tracking is in core) in the schema output. One call → complete project
   surface. Today an agent needs `schema` + `stones` + per-stone calls.
2. **`whet explain <stoneId>`** — one verb combining `stone-config` + `stone-outputs`
   + `stone-source` + dependency ids (and "used by" from the graph). Each `npx whet`
   call pays full project load (import + `onInit`), so *fewer, richer calls* is the
   efficiency lever — for both tokens and wall-clock.
3. **`whet graph [--json]`** — the WS `stones:graph` command has no CLI equivalent;
   "what consumes this stone?" is a question agents ask when tracing pipelines.
4. **Attach mode / MCP.** The expensive part of agent interaction is re-loading the
   project per CLI call. When `serve` is already running (usual during dev), the HTTP
   API (`/api/stones`, `/api/stones/:id/source`) answers instantly from the warm
   process — warm caches, no `onInit`. Options, in increasing effort:
   - Document the HTTP endpoints in the `whet` skill as the preferred path when a
     server is up (cheap; the endpoints already exist).
   - `whet --attach <port> <cmd>`: thin client forwarding a verb to the running
     server and printing the result — same UX, no reload.
   - An MCP server exposing the WS command registry as tools (stones:list,
     stones:refresh, stones:preview …) — the full-fidelity option, and it would give
     agents the *preview* workflow (patch → look at output → persist) that currently
     only the editor has.
5. **`whet stone-schema <type>`** — falls out of config schemas (doc 03); tells an
   agent what's editable with legal values, replacing source-diving.
6. **Skill/docs drift guard** — the `whet` skill states facts that live in three
   repos (verbs in scry, grammar in whet, layout in games). A tiny CI-ish check
   (`whet schema` snapshot compared against the skill's claims) would catch the next
   "stone-cat exists but the skill doesn't know" drift. Low priority, but this review
   found exactly that class of rot.
