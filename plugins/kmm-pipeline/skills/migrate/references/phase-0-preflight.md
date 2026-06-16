# Phase 0 — Preflight

Goal: a verified environment, initialized state, armed hooks. No feature work happens here.

1. **Single-flight check.** If `.kmm/migrations/ACTIVE` exists: switch to resume (state.md) or explicit abandon. Never run two migrations.
2. **Clean tree.** `git status --porcelain` in the main repo must show no tracked changes — untracked `.kmm/`/`.claude/` lines (`??`) are the only entries allowed. Anything else → STOP and surface; never stash someone's work.
3. **Slug + state.** `slug` = kebab-case feature name. Create `.kmm/migrations/<slug>/`, write `state.json` per the state.md schema (phase 0, gates null; `branch`/`base`/`worktree` filled at step 6), empty `journal.ndjson`. Do NOT write `ACTIVE` yet.
4. **Git hygiene.** Append `.kmm/migrations/` to `$(git rev-parse --git-common-dir)/info/exclude` if absent — state must never appear in a PR (this repo has shipped `.kmm` session artifacts into a PR before; the cleanup commit is in its history).
5. **Open-PR collision scan.** `gh pr list --state open` filtered to `kmm/*`/migration branches: does any open PR move files this feature plausibly owns? Renames don't auto-merge — a collision means whoever lands second eats conflicts in moved files. Record overlaps; surface them at G1 (scope around, rebase on, or accept the risk explicitly).
6. **Branch + worktree.** Base = `git symbolic-ref refs/remotes/origin/HEAD` (confirm with the profile's git section; stacked bases happen — if the feature depends on an unmerged migration, surface that at G1). Branch `kmm/<slug>`. Worktree per repo template `../sniper-v2-android-<slug>` via superpowers:using-git-worktrees.
7. **Toolchain probe** (record results in journal; any failure → fix or surface now, not mid-flight):
   - `gh auth status` · `xcodebuild -version` · `pod --version` · `maestro --version`
   - graphify graph present (`graphify-out/graph.json`)? If stale/missing, run `graphify update .` (AST-only) — scout depends on it.
   - Gradle sanity: run the knowledge base's unit-test task for one known-green module with `--dry-run` to confirm task names (task names in docs drift; the knowledge base's verification-commands section is authoritative).
   - **Pre-migration compile baseline**: record the green/red state of the four gate targets (`:shared:compileDebugKotlinAndroid`, `:shared:compileKotlinMetadata`, `:shared:compileKotlinIosArm64`, `:app:compileProductionDebugKotlin`) and the app test-source compile — later failures must be attributable to the migration, and pre-existing breaks get quarantined now, not mid-execute.
8. **Context deltas.** The knowledge base was already read at session start (SKILL.md "Read first") — don't re-read. If the feature plausibly touches charts/indicators or scalper presets, note the matching `AI_GUIDES/*.md` as mandatory reading for scout and workers (CLAUDE.md anchors). If the target repo still carries a legacy `.kmm/project.md`, treat it as read-only history — the plugin knowledge base supersedes it; fold any fact found ONLY there into the knowledge base (with date) as this migration's first knowledge commit.
9. **Arm.** Write `ACTIVE` (slug + state pointer) in the main repo and the worktree. From this moment the guard hooks enforce Law rules 1/4/5 mechanically.
10. **Advance.** Journal `phase-done`, set phase 1.

Exit: state dir initialized, worktree+branch exist, toolchain probed, hooks armed.
