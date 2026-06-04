# dev-harness — Implementation Plan (v3)

Spec: `docs/superpowers/specs/2026-06-02-dev-harness-design.md`. Branch `feat/dev-harness` from `origin/master`.
Order: **prove the load-bearing loop first (Task 1 spike)**, then build outward. Each task ends green (test passes or validate passes) before the next.

---

## Task 1 — Approach-B spike (prove the KEYSTONE) 🔑  [hardened per review]
**Goal:** prove the two load-bearing, empirical unknowns before any other file exists: (1) the Orchestrator can **wake itself unattended and keep driving**, and (2) you can **actually see a worker working** in a narrow tiled pane. Throwaway.
**Steps:**
- Pane A = supervisor loop: polls its own `status` file in-shell (no fswatch/inotify, no coreutils `timeout`); on a new instruction runs `claude -p --model sonnet --permission-mode bypassPermissions --output-format stream-json --verbose --include-partial-messages "<task>"` piped through a **broadened** jq filter that surfaces `text_delta` **+ `thinking_delta` + tool names**; on exit sets `status=done` **only if the expected artifact exists/mtime-newer**.
- Pane B (orchestrator stand-in): worker completion **re-invokes** it via `run_in_background`/Monitor (not a manual poll loop); on each wake it **re-reads `state.json`** to decide the next dispatch — never relies on memory.
- The task must be a **real tool-using coding job** (edit a file, run a check), not `sleep`/prose.
**Accept (all required):**
1. **Repeated automatic wake→read-state→dispatch cycles with ZERO keystrokes** across a run longer than the 10-min ceiling (proves liveness, the #1 risk).
2. Pane A shows **visible tool/think activity** during the work (not one final line) in a narrow pane (proves visibility, the user's #1 ask).
3. Status flips to `done` only with the artifact present; a no-op/refusal does NOT mark done.
4. The worker **loads the bound skills** in the pane's own cwd/env.
**Decision gate:** if the LLM-orchestrator can't stay alive (criterion 1 fails), switch the topology to a **bash driver** that calls `claude -p` only for judgment calls — BEFORE writing the other files. This is the spike's job.

**RESULT — PASSED (2026-06-03).** Both halves proven empirically:
- **Liveness ✅** — orchestrator drove a 3-step run via `run_in_background` completion wakes, re-reading `state.json` from disk each cycle, zero keystrokes; finished `done-3` with all artifacts + journal. AI-orchestrator topology HOLDS (no bash-driver fallback needed).
- **Visibility ✅** — confirmed the broadened filter renders think→tool→answer (the `text_delta`-only filter showed just the final line). **Canonical filter for `role-runner.sh`:**
  ```
  jq -rj 'select(.type=="stream_event") | .event as $e |
    if   $e.type=="content_block_start" and $e.content_block.type=="tool_use" then "\n  🔧 "+$e.content_block.name+" "
    elif $e.type=="content_block_start" and $e.content_block.type=="thinking" then "\n  💭 "
    elif $e.type=="content_block_start" and $e.content_block.type=="text" then "\n  🗨  "
    elif $e.delta.type=="thinking_delta"   then $e.delta.thinking
    elif $e.delta.type=="text_delta"       then $e.delta.text
    elif $e.delta.type=="input_json_delta" then $e.delta.partial_json
    else "" end'
  ```
- **Gotcha pinned:** `claude` is a zsh shell function; the real binary is `/opt/homebrew/bin/claude`. The harness must call the **absolute binary path** (resolved at init), never rely on the interactive shell function. `stream-json` requires `--verbose`; needs `< /dev/null` to avoid the 3s stdin wait.

---
### v1.5 scope (mid agreement)
Build = **one run, full phased pipeline end-to-end**: named team + their skills · phased delivery (UI→logic→wiring) · per-phase Dev→QA · Architect small/structural-replan · both feedback lanes (capture) · restart + single-run resume · lean HTML reviews · all security rails. **Deferred to v2** (do NOT build now): Task 12.5 (multi-run/worktrees/registry/heartbeat) · auto-raising skill-feedback PRs (capture stays) · fanciest HTML theming. Per-phase QA tests only what that phase delivers (anti-deadlock). Tasks 2–13 all stay; only Task 12.5 is dropped from this build.

## Task 2 — Plugin skeleton + lib.sh + assert lib
**Files:** `plugins/dev-harness/.claude-plugin/plugin.json`; `skills/dev-harness/scripts/lib.sh`; `test/_assert.sh`; `test/lib.test.sh`.
**lib.sh:** roles `tech-lead dev qa architect`; `harness_init_layout`, `get_status`/`set_status`, role validation, name→role resolver.
**Accept:** `lib.test.sh` green (layout dirs, status get/set, rejects unknown role, name→role map).

## Task 3 — harness-init.sh (preflight + bootstrap)
**Files:** `scripts/harness-init.sh`; `test/init.test.sh`.
**Does:** PREFLIGHT (tmux, gh, adb+booted emulator, maestro, required plugins/skills) fail-fast; branch from master; `.harness/` layout; capture booted emulator serial → `qa/emulator.lock` (refuse none · `--serial` for >1); tmux `harness` session = 5 tiled panes running `role-runner.sh <role>` + a `log` tail; inside-tmux→switch, else detached+print attach.
**Accept:** `init.test.sh` (in a temp git repo, `--no-tmux --no-branch --no-emulator`) builds the layout + story; preflight failure path returns clear non-zero.

## Task 4 — role-runner.sh + send.sh + poll.sh
**Files:** `scripts/role-runner.sh`, `send.sh`, `poll.sh`; tests.
**role-runner.sh:** loop — wait `status=working` → read inbox + role prompt (abs `${CLAUDE_PLUGIN_ROOT}`) + fold any `feedback.md` → run streamed `claude -p` → exit→`status=done|blocked`.
**send.sh:** write `<role>/inbox.md`, set `working`, nudge. **poll.sh:** read status, `--wait-for`/`--timeout` (≤9 min, re-poll across turns).
**Accept:** tests cover inbox write + status flip + unknown-role refusal + poll wait/timeout.

## Task 5 — feedback.sh (two lanes + name resolution)
**Files:** `scripts/feedback.sh`; `references/feedback-model.md`; tests.
**Does:** `feedback <name|role>: …` → `.harness/<role>/feedback.md`; `skill-feedback <skill>: …` → `~/.dev-harness/skill-feedback/<skill>.md` (continuous, not a phase). Name→role + ambiguous-first-name handling.
**Accept:** tests: persona + role targets both resolve; skill lane appends to the durable store.

## Task 6 — HTML interaction layer
**Files:** `assets/theme.css` (derived from feature-analyzer canonical); `scripts/render-review.sh`; `references/html-interaction.md`.
**Does:** `render-review.sh <kind> <payload>` → themed HTML (sidebar, header, Original-Story tab where relevant, comment boxes, Q&A, copy button) → open/print path. Kinds: story · plan · questionnaire · verdict · summary.
**Accept:** sample render opens; copy-block format parseable by the Orchestrator.

## Task 7 — DEFERRED: QA uses qa-autopilot (split postponed)
**Decision (user):** do NOT split qa-autopilot for v1.5. The QA agents use the existing **`qa-autopilot`** skill directly — Rohit for QA mindset + flake-vs-real, Bharat-QA for single-flow Maestro authoring + execution. Dedicated `qa-lead`/`qa-junior` skills are to be authored later.
**Accept:** rohit/bharat-qa agents + skill-bindings reference `qa-autopilot`; no qa-lead/qa-junior plugins; `claude plugin validate .` passes.

## Task 8 — Worker agent defs (sonnet)
**Files:** persona agents `agents/bharat-dev.md`, `agents/bharat-qa.md` (`model: sonnet`, scoped tools, clean-code / qa-autopilot binding). (Plus opus lead agents manish/mohit-dev/rohit/mohit-arch.)
**Accept:** validate passes; agents discoverable.

## Task 9 — Protocol + role prompts + restart + skill-bindings
**Files:** `references/protocol.md`, `skill-bindings.md` (drop dsa-patterns/app-strategy-builder), `restart.md`, `role-{tech-lead,dev,qa,architect}.md`.
**Encodes:** phased delivery, per-chunk Dev loop, QA serial + tag-check, Architect clean-room review + structural-replan, streaming, HTML gates, checkpoint/restart.
**Accept:** each role file references skill-bindings + abs paths; grep checks pass.

## Task 10 — Orchestrator playbook
**Files:** `references/orchestrator.md`.
**Encodes:** preflight → init → Tech-Lead (+phase plan + HTML gate) → per-phase Dev→QA loop → PR → Architect routing (small no-reQA / structural replan) → final QA → caps (QA 7 · Arch 3 · global ≤3) → commands (feedback/skill-feedback/restart/status/--auto/--resume) → log.md ledger.
**Accept:** grep checks for each helper script + each role + each command.

## Task 11 — SKILL.md + /harness command
**Files:** `skills/dev-harness/SKILL.md` (overview + 9 hard rules + loop bounds, lean), `commands/harness.md` (Orchestrator entry, reads orchestrator.md).
**Accept:** frontmatter valid; command resolves references.

## Task 12 — Catalog + README + version bumps
**Files:** `.claude-plugin/marketplace.json` (+ dev-harness entry, top-level bump), `README.md` row. 4-place rule for all 3 new plugins.
**Accept:** `claude plugin validate .` passes; versions consistent.

## Task 12.5 — Crash recovery, resume & multi-run
**Files:** `references/resume.md`; resume helpers in `lib.sh` (state.json read/write, registry, heartbeat, stale-lock); `harness-init.sh` (run-id, `.harness/runs/<id>/`, registry entry, own git worktree when same-repo concurrent); `harness-resume` path in the orchestrator + a `render-review.sh` "picker" kind; tests.
**Does:** durable `state.json` + append `log.md` at every transition; heartbeat; `~/.dev-harness/registry.json`; `/harness --resume` (registry → HTML picker → rebuild tmux + panes → re-pin emulator → re-send in-flight instruction). Idempotent re-dispatch (temp-then-rename writes; "next unticked chunk").
**Accept:** kill a run mid-task in a temp repo → `--resume` rebuilds state from disk and continues from the in-flight step; two runs register without collision; stale-lock takeover works, fresh-lock is refused.

## Task 13 — Smoke + sweep + PR
**Files:** `test/SMOKE.md` (on-device, tmux, streaming, phased, feedback lanes, restart, HTML gates).
**Does:** run all `*.test.sh`; validate; document the manual smoke; open PR to master (never push direct).
**Accept:** all unit tests green; validate passes; SMOKE.md documents what the units can't.

---

## Notes
- Tasks 2–6 are the harness mechanics; 7–8 are dependencies; 9–11 the brains; 12–13 ship.
- Authoring discipline: small, precise SKILL files, hard imperative rules; detail in references only when load-bearing.
- Open risks tracked in the spec (streaming-pane readability; pane-runtime skill loading) — both validated by the Task 1 spike.
