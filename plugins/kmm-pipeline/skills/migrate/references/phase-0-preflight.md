# Phase 0 — Preflight

Goal: a verified environment, initialized state, armed hooks. No feature work happens here.

1. **Single-flight check.** If `.kmm/migrations/ACTIVE` exists: switch to resume (state.md) or explicit abandon. Never run two migrations.
2. **Clean tree.** `git status --porcelain` in the main repo must be empty (untracked `.kmm/`, `.claude/` entries are fine). Dirty → STOP and surface; never stash someone's work.
3. **Slug + state.** `slug` = kebab-case feature name. Create `.kmm/migrations/<slug>/`, write `state.json` (phase 0, gates null), empty `journal.ndjson`. Do NOT write `ACTIVE` yet.
4. **Git hygiene.** Append `.kmm/migrations/` to `$(git rev-parse --git-common-dir)/info/exclude` if absent — state must never appear in a PR (this repo has shipped `.kmm` session artifacts into a PR before; the cleanup commit is in its history).
5. **Branch + worktree.** Base = `git symbolic-ref refs/remotes/origin/HEAD` (confirm with the profile's git section; stacked bases happen — if the feature depends on an unmerged migration, surface that at G1). Branch `kmm/<slug>`. Worktree per repo template `../sniper-v2-android-<slug>` via superpowers:using-git-worktrees.
6. **Toolchain probe** (record results in journal; any failure → fix or surface now, not mid-flight):
   - `gh auth status` · `xcodebuild -version` · `pod --version` · `maestro --version`
   - graphify graph present (`graphify-out/graph.json`)? If stale/missing, run `graphify update .` (AST-only) — scout depends on it.
   - Gradle sanity: run the profile's unit-test task for one known-green module with `--dry-run` to confirm task names (task names in docs drift; the profile's "Manual QA / verification commands" section is authoritative).
7. **Context load.** Read `.kmm/project.md` fully. If the feature plausibly touches charts/indicators or scalper presets, note the matching `AI_GUIDES/*.md` as mandatory reading for scout and workers (CLAUDE.md anchors).
8. **Arm.** Write `ACTIVE` (slug + state pointer) in the main repo and the worktree. From this moment the guard hooks enforce Law rules 1/4/5 mechanically.
9. Journal `phase-done`, set phase 1.

Exit: state dir initialized, worktree+branch exist, toolchain probed, hooks armed.
