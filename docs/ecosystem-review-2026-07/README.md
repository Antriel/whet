# Whet Ecosystem Review — July 2026

A review of Whet and how it's actually used across the ecosystem: this repo, the
`gooye-2` game (modern single-player layout), the Scry editor (`scry-app` +
`scry/whetstones/`), and the older multi-sub-project layout (`SnowFight`).

| Doc | Contents |
|---|---|
| [01-whet-core-review.md](01-whet-core-review.md) | Core repo findings: docs gaps, id stability, ConfigStore lifecycle, small API rough edges |
| [02-scry-integration.md](02-scry-integration.md) | Assessment of the Scry/Stone-Inspector integration and what should migrate into whet core |
| [03-data-driven-stones.md](03-data-driven-stones.md) | The StoneStore idea: how far to push data-driven pipelines, design sketch, incremental path |
| [04-llm-ergonomics-and-skills.md](04-llm-ergonomics-and-skills.md) | CLI grammar reference, what changed in the two skills, further agent-ergonomics ideas |

## TL;DR

- **The core is in good shape.** The recent perf work (memo contexts, cache-metadata
  `listIds`, code-aware self-hash, partial generation) landed well; the architecture
  held up under three quite different project shapes. The biggest core gaps are
  *documentation* (README is a stub) and a few lifecycle rough edges (implicit-id
  instability vs ConfigStore keys, orphaned ConfigStore entries).
- **The Scry integration is better-layered than "vibe-coded" suggests** — the
  Project-level config-view API does the real work and the plugin is mostly transport.
  The main structural recommendation: the generic introspection CLI verbs
  (`stones`, `stone-config`, `stone-cat`, `refresh`, …) only need `Project` and
  should live in whet core, not in ScryStone.
- **Data-driven stones already have the right seed: `StoneFactory`.** The proposed
  `StoneStore` is "StoneFactory with a generic `createEntry`" — a JSON file of
  `{id, type, config, mount}` entries plus a stone-type registry and a `$stone`/`$router`
  config reviver. The keystone enabler is per-class **config schemas**, which also buy
  generic editor forms and LLM-faced validation. Keep `onInit`/build-mode logic in script.
- **Both skills were updated** (`~/.claude/skills/whet`, `whet-pipeline`): the outdated
  "no CLI command" framing is gone, `stone-cat` is documented, and there's now a CLI
  grammar section (option-before-command ordering, `+` chaining, first-segment rule).
