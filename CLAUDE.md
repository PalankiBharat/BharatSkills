# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude Code **plugin marketplace** (`punchhq-skills`) — not application code. It distributes skills/commands/hooks for Android + KMM development workflows. There is no build system; "shipping" means committing JSON/Markdown/shell/Python and bumping versions. Users install via `/plugin marketplace add PunchHQ/claude-code-skills` and then `/plugin install <name>@punchhq-skills`.

## Validation

```shell
claude plugin validate .
```

Run after any edit under `plugins/` or `.claude-plugin/`. There are no other repo-level commands (no tests, no lint, no build).

## Architecture

Two layers — the catalog, and the plugins it points at.

**1. Catalog: `.claude-plugin/marketplace.json`**
Single source of truth listing every plugin and its installable metadata (`name`, `source`, `description`, `version`, `category`, `tags`, `keywords`). `metadata.pluginRoot` is `./plugins`. The top-level `metadata.version` is the marketplace version itself; each plugin entry also carries its own `version`.

**2. Plugins: `plugins/<plugin-name>/`**
Every plugin has `.claude-plugin/plugin.json` (canonical `name`/`description`/`version`) plus any combination of:

- `skills/<skill-name>/SKILL.md` — model-invoked skill. The YAML frontmatter `description` is what triggers auto-invocation; write it to maximize correct triggering, not as marketing copy. Supporting files go in `references/`, `prompts/`, `schemas/`, `scripts/` next to SKILL.md and are referenced from it.
- `commands/<name>.md` — slash command (e.g. `om-pipeline` exposes `/om`, `/om-bramha`, `/om-vishnu`). User-invoked, not auto-triggered.
- `hooks/hooks.json` + `scripts/` or `hooks/*.py` — event hooks. Real examples in-tree:
  - `clean-code-plugin` — `UserPromptSubmit` shell hook that injects SKILL.md content into every prompt.
  - `skill-feedback-plugin` — `PostToolUse` matcher `Skill|Read|Bash` for invocation tracking.
  - `kmm-migration-workflow` — `SessionStart` + `PreToolUse`/`PostToolUse` Python hooks (frozen-baseline guard, write-notice).
  Hook commands reference `${CLAUDE_PLUGIN_ROOT}` for plugin-local paths.

Plugin directory names don't have to match plugin `name` — e.g. directory `skill-feedback-plugin/` contains plugin `skill-feedback`; directory `clean-code-plugin/` contains plugin `clean-code`. The marketplace `source` path is the authoritative pointer.

## The version-bump rule (load-bearing)

Any plugin change must update **all four** places, in lockstep:

1. `plugins/<plugin>/.claude-plugin/plugin.json` → `version`
2. `.claude-plugin/marketplace.json` → that plugin's entry `version`
3. `.claude-plugin/marketplace.json` → top-level `metadata.version` (marketplace itself)
4. `README.md` → the row in the "Available Plugins" table

A version drift between (1) and (2) ships a broken catalog. Drift between (3) and the rest means users won't get the update at all.

## Editing descriptions

Don't rewrite plugin descriptions on routine version bumps — they're tuned for skill triggering and user-facing clarity. When a description change is explicitly requested, simplify to **what + how** (one or two sentences), not an exhaustive feature list. The `description` in `plugin.json` and the `description` in the marketplace entry serve different audiences (model trigger vs. catalog browse) and can legitimately differ; check both when editing either.

## Adding a new plugin

1. `plugins/<name>/.claude-plugin/plugin.json` with `name`, `description`, `version`.
2. Add `skills/`, `commands/`, and/or `hooks/` per the architecture section.
3. Append a `plugins[]` entry to `.claude-plugin/marketplace.json` (set `source: "./plugins/<dir>"`).
4. Add the row to the README table.
5. Bump top-level `metadata.version` in `marketplace.json`.
6. `claude plugin validate .`

## Always Create an PR
never push directly to master, always create an PR with concise body describing the change.
