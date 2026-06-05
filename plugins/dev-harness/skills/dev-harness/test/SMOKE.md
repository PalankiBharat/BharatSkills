# Smoke procedure (manual — tmux + real device + real agents)

The bash unit suite proves only file I/O (mailbox, status, send/poll, feedback, render, guard).
The agent behaviour + tmux panes + streaming + emulator + subagent dispatch can't be unit-tested.
Run this once on a project repo before declaring the harness usable.

## Prereqs
`tmux`, `gh` (authed), `jq`, a booted Android emulator (`adb devices` shows one), `maestro`, and the
plugins installed where the panes run: dev-harness, feature-analyzer, clean-code, bug-finder,
legacy-refactor, preview-compose, figma-to-compose, kmm-*, qa-autopilot, review-pr.

## Steps
1. From an app repo on `master`, run: `/harness "Change the dashboard headline to 'Hello world'"`.
2. **Panes:** `tmux ls | grep harness`; the window has 5 tiled panes (tech-lead, dev, qa, architect, log).
3. **Branch + lock:** `git branch --show-current` = `harness/<slug>-<date>`; `cat .harness/qa/emulator.lock` matches `adb devices`; `.harness/` is gitignored.
4. **Visibility:** each pane STREAMS live work (think 💭 + tool 🔧 + text 🗨), not one final line.
5. **Agents/models (token-cost critical):** each pane's `/model` must match `role_model` — orchestrator/tech-lead/architect on **opus**, dev/qa on **opusplan** (check the pane header / run `/model` in a pane). The dev pane (Mohit-Dev) must **spawn Bharat-Dev via the Agent tool** and let him type — confirm a Bharat-Dev subagent on **sonnet** appears in the dev transcript and that Mohit-Dev did NOT edit app files directly. Same for QA (Rohit spawns Bharat-QA on sonnet). If no junior subagent appears, the spawn is broken and tokens will be all-opus.
6. **Adaptive flow:** Manish writes a flow weight at the top of `artifacts/spec.md`; for this tiny story it should pick "small change", not a full feature pipeline.
7. **HTML gates:** the plan gate opens an HTML page in the browser; answers paste back and the run continues.
8. **Feedback:** in the main session say `feedback for mohit: also handle empty state` → appears in `.harness/dev/feedback.md`; `skill-feedback qa-autopilot: prefers text selectors` → appears under `~/.dev-harness/skill-feedback/`.
9. **Restart:** `restart dev` → checkpoint handoff written, pane respawns, RESUME continues from the worklog.
10. **Resume:** kill the tmux session mid-run; in a fresh session say `continue` → it rebuilds the panes and re-sends the in-flight instruction from `state.json`.
11. **Security guard:** in any pane, attempt `git push --force` or `adb kill-server` → the PreToolUse guard BLOCKS it. `--force-with-lease` on the run's own branch is allowed.
12. **Isolation:** mid-run `git diff --name-only` — Dev touched only `app/src/**`, QA only `.maestro/**`/`artifacts/qa-*`.
13. **Caps:** force repeated QA fails → after 7 it escalates to you; Architect after 3; global after 3 QA→Arch cycles.
14. **Done:** final summary in `log.md`; a draft PR exists on the run's branch.

## v2 smoke
15. **Sandbox:** run `/harness --sandbox "<story>"`; in a pane try to read `~/.ssh/id_rsa` or write `~/.bashrc` → blocked by the OS sandbox; a repo edit + `~/.maestro` write still work. (`/sandbox` panel shows the resolved config.)
16. **Multi-run:** run two stories with `/harness --worktree "<A>"` and `/harness --worktree "<B>"`. Verify two worktrees (`git worktree list` shows `.harness-worktrees/<id>`), two tmux sessions (`tmux ls | grep harness-`), and two registry entries (`jq .runs ~/.dev-harness/registry.json`). Each on its own emulator.
17. **Resume picker:** kill one run's tmux session; `/harness --resume` (or "continue") → an HTML picker lists the resumable run (stale heartbeat) → choose it → its session + emulator reattach and it continues from `state.json`.
18. **No double-drive:** while a run is alive (fresh heartbeat + session), a second `--resume` on it refuses (lock held).
