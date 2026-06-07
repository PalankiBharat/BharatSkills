# KMM Migration Autopilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tmux-orchestrated headless-phase-pipeline ("autopilot") mode to the `kmm-migration` skill, so an interactive orchestrator runs Phases 0+A with the human and then auto-drives Phases B→I as fresh headless `claude` worker sessions, escalating only an irreversible decision class — plus the agreed skill-doc surgery (Phase F smoke removal, Phase I build-flavor split, `kmm-qa-autopilot` reference cleanup).

**Architecture:** The orchestrator is a normal interactive `claude` session (role=orchestrator) that, from Phase B onward, spawns one `claude -p` worker per phase in its own tmux window. Workers self-bootstrap via the existing `resume_session.py` SessionStart hook, run exactly one phase, and communicate back through files under `.kmm/migrations/kmm/<feature>-<depth>/orchestration/` (`phase-<X>.status`, `decision-request.md`, `decision-response.md`). Mode is signalled by env vars (`KMM_AUTOPILOT_ROLE`, `KMM_AUTOPILOT_PHASE`) that both the model and the hook read. The four irreversible decision classes (dep swaps, behavior-changing fixes, scope/plan flips, real-money journeys) plus three inherent escalations (device/login pre-flight, PII gate, first-time detekt) pause via the file protocol; everything else is auto-decided with logged reasoning.

**Tech Stack:** Bash (tmux driver + helper scripts), Python 3 (existing SessionStart hook), Markdown (skill + reference docs), `claude` CLI headless mode (`-p`, `--dangerously-skip-permissions`). No app build system — this is a plugin marketplace repo; validation is `claude plugin validate .` plus the repo's `scripts/tests/` bash/pytest harness.

**Reference:** Design spec at `docs/superpowers/specs/2026-06-07-kmm-migration-autopilot-design.md`.

**Working location:** Worktree `../claude-code-skills-kmm-autopilot`, branch `feat/kmm-autopilot-orchestration` (already created). All paths below are relative to the repo root unless absolute.

**Skill root shorthand:** `SK = plugins/kmm-migration-workflow/skills/kmm-migration`. `PR = plugins/kmm-migration-workflow` (plugin root).

---

## Group A — Skill-doc surgery (independent of the autopilot layer)

### Task A1: Remove `kmm-qa-autopilot` references

**Files:**
- Modify: `plugins/kmm-migration-workflow/hooks/resume_session.py:264-269`
- Modify: `SK/references/phases/phase-i-qa.md:9`

- [ ] **Step 1: Write the failing assertion**

Run: `grep -rn "kmm-qa-autopilot" plugins/kmm-migration-workflow/`
Expected NOW: 2 matches (`hooks/resume_session.py`, `references/phases/phase-i-qa.md`). This is the RED state — the refs still exist.

- [ ] **Step 2: Fix the resume hook "all complete" message**

In `plugins/kmm-migration-workflow/hooks/resume_session.py`, replace the all-phases-complete message body (currently lines 264-269) so it no longer names `kmm-qa-autopilot`:

```python
        lines.append(
            "All phases through I report `complete` — PR opened, code review "
            "resolved, and the in-skill Phase I parity loop converged. If the "
            "PR has not yet merged, the next action is merge. If the session is "
            "post-merge, offer worktree cleanup per Phase E post-session steps."
        )
```

- [ ] **Step 3: Remove the standalone-tool note in phase-i-qa.md**

In `SK/references/phases/phase-i-qa.md`, delete line 9 entirely (the parenthetical:
`(The standalone `kmm-qa-autopilot` skill still exists as a separate, optional, user-triggered tool, but it is **no longer the Phase I mechanism** — Phase I is self-contained.)`)
and the blank line that follows it, so the section flows from the "loop reuses the migration's discipline" paragraph straight to **Inputs:**.

- [ ] **Step 4: Run the assertion to verify it passes**

Run: `grep -rn "kmm-qa-autopilot" plugins/kmm-migration-workflow/`
Expected: no matches (exit code 1, empty output).

- [ ] **Step 5: Commit**

```bash
git add plugins/kmm-migration-workflow/hooks/resume_session.py \
        plugins/kmm-migration-workflow/skills/kmm-migration/references/phases/phase-i-qa.md
git commit -m "ref:(kmm) drop kmm-qa-autopilot references — Phase I is self-contained"
```

---

### Task A2: Phase F — remove the runtime-crash smoke, keep the heatmap draft

The runtime-crash smoke moves out of Phase F entirely (Phase I's parity loop now exercises runtime). F.5 becomes heatmap-draft-only; F loses its device dependency; every "F.5 smoke" cross-reference becomes "F.3" (build+tests).

**Files:**
- Modify: `SK/references/phases/phase-f-validation.md` (intro paras, F.3 sim note, F.5, F.6, F.7-adjacent gates)

- [ ] **Step 1: Write the failing assertion**

Run: `grep -nE "smoke|ProductionRelease|crash" SK/references/phases/phase-f-validation.md | wc -l`
Expected NOW: a non-zero count (multiple smoke/ProductionRelease mentions). RED.

- [ ] **Step 2: Rewrite the intro (lines 3–7)**

Replace the three intro paragraphs (the `**Purpose.**`, `**What moved out of Phase F.**`, and `**The smoke test stays...**` blocks) with:

```markdown
**Purpose.** Prove the migration is structurally sound and behavior-preserving *as far as automated static checks can show*, then hand a clean, installable build to Phase G (PR), Phase H (code-review intake), and Phase I (parity QA). Multi-layered automated sanity check: code, docs, build, tests, pre-merge integration. **Behavioral parity QA — and any runtime exercise of the app — is NOT in this phase**; it runs in-skill at Phase I, as an autonomous agent-device replay loop against the frozen runtime golden. Any blocker here → loop back through the relevant prior phase → re-validate.

**What moved out of Phase F.** The old F.6 user-driven manual-QA gate and F.7 "migration complete" sign-off are gone. The runtime-crash smoke is also gone — Phase I's parity loop launches and drives the app, so a separate launch smoke here is redundant (and Phase I would catch a dead build on its first iteration anyway). Phase F's job is now purely static + build-time: *does it build on both platforms, are the baselines green, and does it integrate with the latest base branch?* The heatmap is still **drafted** here (F.5) because Phase G embeds it into the PR body and the Phase I loop consumes it (filling its Result cells).

**No device is required for Phase F.** Removing the smoke removes Phase F's only device/emulator dependency. The HTTP-parity checks in F.3 that use `agent-device network` remain device-dependent *only when the project produced a timeout/server-registration table in Phase A*; when present, surface the device requirement at the start of F.3 (not after a long build).
```

- [ ] **Step 3: Fix the F.3 iOS-sim cross-reference to F.5**

In F.3, the `iosSimulatorArm64Test` bullet contains "(see F.5 note)". Change that parenthetical to "(provision + boot the simulator before this task)" so it no longer points at the deleted smoke note. Exact replacement for that bullet:

```markdown
  - `<dest>/iosSimulatorArm64Test` (or equivalent, if host supports) — same commonTest baselines on iOS runtime. **Requires a provisioned + booted simulator device** (provision + boot it before this task) — a cold/missing sim yields a misleading "Xcode does not support simulator tests" error, not a code failure.
```

- [ ] **Step 4: Replace F.5 with heatmap-draft-only**

Replace the entire `### F.5 — Runtime-crash smoke + heatmap draft (in parallel)` section (its heading through line 106, just before `### F.6`) with:

```markdown
### F.5 — Heatmap draft

Drafted as a **pre-QA checklist** that Phase G embeds into the PR body and the Phase I parity loop consumes. Result column starts `TBD` and is **never** pre-filled — it is filled during the in-skill parity QA (Phase I), not here.

**Primary source: `journeys.md`.** Each row in the heatmap maps directly to one entry in the journey catalog. An **Opus subagent** reads `journeys.md` (produced by Phase A) and renders one heatmap row per journey, carrying a pointer to that journey's frozen golden reference (the `golden/<journey>/` directory under the session's migration root). diff-derived behavior discovery is no longer the source here — it lives in Phase A as the coverage cross-check that validates `journeys.md` is complete.

Format (tickable markdown saved as `heatmap.md`):

| Journey | User does | Expects to see | Golden ref | Result |
|---|---|---|---|---|
| <journey name from journeys.md> | <action from journeys.md> | <expected output from journeys.md> | `golden/<journey>/` | TBD |
| ... | ... | ... | ... | TBD |
```

- [ ] **Step 5: Fix the F.6 surgical re-validation scope (smoke → F.3 only)**

In F.6, the "Smoke crash" loop-back row no longer applies — delete that table row. Then update the surgical re-validation bullet: replace "re-run F.3 (build + tests, incl. JUnit-XML execution check) + F.5 smoke. **Skip** F.1..." with:

```markdown
- **Surgical fix (≤5 LOC, single file, no new types / methods / public-API signatures):** re-run F.3 (build + tests, incl. JUnit-XML execution check) only. **Skip** F.1 (goal/doc consistency unchanged), F.2 (code quality, single-file is trivially reviewable), F.4 (pre-merge integration — only if the base moved since the last F.4). Example: changing a single timeout literal, fixing one off-by-one, swapping one constant.
```

Also update the announce-example to drop "+ F.5": `*"Surgical: 1-line socket timeout swap, re-running F.3 only"*`.

- [ ] **Step 6: Fix the phase-specific gates**

In the closing `## Phase-specific gates`, replace the smoke gate line:
`- Smoke confirms the ProductionRelease build installs + launches **crash-free**; `heatmap.md` is drafted with `TBD` cells and never pre-filled (it's filled during Phase I parity QA).`
with:
```markdown
- `heatmap.md` is drafted with `TBD` cells and never pre-filled (it's filled during Phase I parity QA). Phase F runs no runtime smoke — the build's runtime health is established by the Phase I parity loop.
```

- [ ] **Step 7: Run assertions to verify**

Run: `grep -nE "F\.5 smoke|Runtime-crash smoke|Smoke crash" SK/references/phases/phase-f-validation.md`
Expected: no matches.
Run: `grep -nc "Heatmap draft" SK/references/phases/phase-f-validation.md`
Expected: ≥1.

- [ ] **Step 8: Commit**

```bash
git add SK/references/phases/phase-f-validation.md
git commit -m "refactor(kmm): drop Phase F runtime smoke — Phase I parity loop covers runtime"
```
(Expand `SK` to the full path in the actual command.)

---

### Task A3: Phase I — ProductionDebug loop + binding ProductionRelease final-sanity

The iterative A/B loop runs on ProductionDebug (logs available); a final ProductionRelease A/B pass is the **binding parity-truth gate** (Debug skips R8 → serialization false-greens). Also fix the I.2.4 re-validation reference to the now-deleted F.5 smoke.

**Files:**
- Modify: `SK/references/phases/phase-i-qa.md` (I.1.2, new I.2.8 final-sanity, I.2.4.4–5, I.3 promise, gates)

- [ ] **Step 1: Write the failing assertion**

Run: `grep -nc "ProductionDebug" SK/references/phases/phase-i-qa.md`
Expected NOW: 0 (the phase currently only mentions ProductionRelease). RED.

- [ ] **Step 2: Convert the loop build flavor (I.1 step 2)**

Replace I.1 step 2 with a two-flavor description:

```markdown
2. **Build APKs per the two-stage flavor policy.** The iteration loop runs on **`ProductionDebug`** so logcat is available for diagnosis; the binding final-sanity pass runs on **`ProductionRelease`** (R8 — see I.2.8). Build **master ProductionDebug ONCE** and reuse it across all iterations; **only the migrated `ProductionDebug` side rebuilds after a fix**. The `ProductionRelease` pair is built later, at I.2.8, not here. Any single A/B comparison uses the **same flavor on both legs** (master-Debug vs migrated-Debug in the loop; master-Release vs migrated-Release at I.2.8) — never cross-flavor.
```

- [ ] **Step 3: Update the loop's replay/rebuild steps to ProductionDebug**

In I.2.4 step 5, replace "Rebuild only the migrated APK (master is untouched, never rebuilt)" with:
```markdown
   5. **Rebuild only the migrated `ProductionDebug` APK** (master Debug is untouched, never rebuilt) and **re-run only the affected probe** — not the whole catalog.
```
In I.2.4 step 4, replace "re-validate at the Phase F.6 mechanical scope — surgical (≤5 LOC, single file, no new types/signatures) → F.3 + F.5 smoke; non-surgical → full F.1." with:
```markdown
   4. **Commit** (two-commit cadence), then **re-validate at the Phase F.6 mechanical scope** — surgical (≤5 LOC, single file, no new types/signatures) → F.3 (build + tests) only; non-surgical → full F.1. Announce the scope + one-line justification.
```

- [ ] **Step 4: Add I.2.8 — binding ProductionRelease final-sanity pass**

After I.2.7 (iOS forward-check), add a new sub-step that gates loop exit:

```markdown
8. **(Loop-exit gate) ProductionRelease final-sanity A/B.** A green ProductionDebug loop is **necessary but not sufficient** — Debug skips R8, which can strip `@Serializable` keep rules that only fail under Release, producing serialization false-greens (per `references/runtime-golden.md`). So before the completion promise can be emitted: build the **master + migrated `ProductionRelease`** pair (R8-minified shipped artifact), and re-run **every catalog journey's replay probe** master-Release vs migrated-Release with `compare-golden.py` exact-diff. **Parity is NOT declared green until this Release pass is all-🟢.** A Release-only divergence (green in Debug, red in Release) is a real parity bug — diagnose and fix it through the same I.2.4 workflow (its failing-test-first proof runs against the Release artifact), then rebuild the migrated Release side and re-run the affected Release probe. The master Release APK is built once and reused like the Debug master.
```

- [ ] **Step 5: Fold the Release gate into the completion promise (I.3)**

Replace the verbatim completion promise with:

```markdown
> Every catalog journey is 🟢 with a real anchor reached **on the ProductionRelease A/B pass (I.2.8)**, zero open 🔴, zero ⚪-indeterminate, the iOS forward-check passed-or-is-a-named-gap, and any remaining finding is an explicitly user-deferred recorded follow-up.
```

Add a convergence-guard bullet under "Convergence guards (non-negotiable)":
```markdown
- **Release-sanity is binding.** The completion promise may not be emitted on Debug-loop greenness alone — the ProductionRelease A/B pass (I.2.8) must be all-🟢 first. A Debug-green / Release-red state is an open 🔴.
```

- [ ] **Step 6: Update the phase-specific gates**

Replace the gate bullet `- **Replay is the default; live A/B is the exception**...` is fine; ADD a new gate bullet:
```markdown
- **ProductionDebug for the loop, ProductionRelease for the binding final-sanity** — parity is not green until the I.2.8 Release A/B pass is all-🟢 (Debug skips R8 → serialization false-greens).
```

- [ ] **Step 7: Run assertions**

Run: `grep -nc "ProductionDebug" SK/references/phases/phase-i-qa.md` → Expected: ≥3.
Run: `grep -nc "I.2.8\|final-sanity\|ProductionRelease final" SK/references/phases/phase-i-qa.md` → Expected: ≥2.
Run: `grep -n "F.5 smoke" SK/references/phases/phase-i-qa.md` → Expected: no matches.

- [ ] **Step 8: Commit**

```bash
git add SK/references/phases/phase-i-qa.md   # (expand SK)
git commit -m "feat(kmm): Phase I ProductionDebug loop + binding ProductionRelease final-sanity"
```

---

## Group B — Autopilot orchestration layer

### Task B1: Probe the `claude` CLI headless capability (verification, no code change)

Some flags are version-dependent. Lock the exact flag-set the scripts will use BEFORE writing them, so the scripts target the installed CLI.

**Files:** none (records findings into the next tasks' scripts).

- [ ] **Step 1: Print the CLI version + relevant flags**

Run:
```bash
claude --version
claude --help 2>&1 | grep -iE "print|dangerously|model|max-turns|output-format|session|permission-mode|setting"
```
Expected: confirms `-p/--print`, `--dangerously-skip-permissions`, `--model`. Note whether `--max-turns`, `--output-format`, and a no-session-persistence flag exist (names vary by version).

- [ ] **Step 2: Smoke a one-shot headless run that proves hooks fire**

Run (from the worktree root, on a non-kmm branch so the resume hook stays silent — this only proves headless + exit code):
```bash
echo "say only the word PONG" | claude -p "respond with exactly: PONG" --dangerously-skip-permissions; echo "exit=$?"
```
Expected: output contains `PONG`, `exit=0`. Confirms run-to-completion + clean exit code.

- [ ] **Step 3: Record the locked flag-set**

Write the confirmed worker invocation into a comment at the top of `scripts/run-phase-worker.sh` (Task B3). Baseline (adjust to what Step 1 confirmed):
```
claude -p "<prompt>" --dangerously-skip-permissions [--max-turns <N> if supported] [--model <m> if pinning]
```
If `--max-turns` exists, set it high (e.g. 400) so a long phase (D, I) cannot silently truncate; if it does NOT exist, note that workers rely on the phase's own completion and the status file. No commit (no file change yet).

---

### Task B2: `resume_session.py` — emit an autopilot mode banner

The hook already computes the active phase. Add deterministic mode signalling: when `KMM_AUTOPILOT_ROLE` is set, append a role banner so the model's behaviour (worker = run-one-phase-and-exit; orchestrator = drive-the-loop) does not depend on it "noticing" an env var. Worker mode also cross-checks `KMM_AUTOPILOT_PHASE` against the computed active phase.

**Files:**
- Modify: `plugins/kmm-migration-workflow/hooks/resume_session.py`
- Test: `plugins/kmm-migration-workflow/hooks/tests/test_resume_autopilot.py` (create; create `tests/` dir if absent)

- [ ] **Step 1: Write the failing test**

Create `plugins/kmm-migration-workflow/hooks/tests/test_resume_autopilot.py`:

```python
import importlib.util, os
from pathlib import Path

HOOK = Path(__file__).resolve().parents[1] / "resume_session.py"
spec = importlib.util.spec_from_file_location("resume_session", HOOK)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)


def test_worker_banner_present_and_phase_matches(monkeypatch):
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "worker")
    monkeypatch.setenv("KMM_AUTOPILOT_PHASE", "D")
    banner = mod.autopilot_banner(active_phase_id="D")
    assert "AUTOPILOT WORKER MODE" in banner
    assert "run only the active phase" in banner.lower()
    assert "decision-request" in banner
    assert "phase-D.status" in banner


def test_worker_phase_mismatch_warns(monkeypatch):
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "worker")
    monkeypatch.setenv("KMM_AUTOPILOT_PHASE", "C")
    banner = mod.autopilot_banner(active_phase_id="D")
    assert "MISMATCH" in banner


def test_orchestrator_banner(monkeypatch):
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "orchestrator")
    banner = mod.autopilot_banner(active_phase_id="B")
    assert "AUTOPILOT ORCHESTRATOR MODE" in banner
    assert "spawn" in banner.lower()


def test_no_banner_without_role(monkeypatch):
    monkeypatch.delenv("KMM_AUTOPILOT_ROLE", raising=False)
    assert mod.autopilot_banner(active_phase_id="B") == ""
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m pytest plugins/kmm-migration-workflow/hooks/tests/test_resume_autopilot.py -q`
Expected: FAIL — `AttributeError: module has no attribute 'autopilot_banner'`.

- [ ] **Step 3: Implement `autopilot_banner`**

Add to `resume_session.py` (before `format_report`):

```python
def autopilot_banner(active_phase_id: str | None) -> str:
    """Emit a deterministic mode banner when running under the tmux autopilot.

    Mode is signalled by KMM_AUTOPILOT_ROLE so worker/orchestrator behaviour
    does not depend on the model noticing an env var.
    """
    import os
    role = os.environ.get("KMM_AUTOPILOT_ROLE")
    if not role:
        return ""
    if role == "worker":
        want = os.environ.get("KMM_AUTOPILOT_PHASE")
        lines = ["", "### AUTOPILOT WORKER MODE"]
        if want and active_phase_id and want != active_phase_id:
            lines.append(
                f"⚠️ **PHASE MISMATCH** — orchestrator asked for phase `{want}` "
                f"but the serialized state's active phase is `{active_phase_id}`. "
                f"Do NOT run. Write `orchestration/phase-{want}.status` = "
                f"`FAILED` with this mismatch as the reason, then stop."
            )
            return "\n".join(lines) + "\n"
        p = active_phase_id or want or "?"
        lines += [
            f"You are a headless phase worker for phase **{p}**. Run only the "
            "active phase to completion (including its blocking retro). Do NOT "
            "advance to the next phase and do NOT wait for interactive input.",
            "- First, check `orchestration/decision-response.md` — if present, "
            "consume the human's answer(s), then delete it and continue.",
            "- On any of the four gated decision classes (dependency/library "
            "swap, behavior-changing fix, scope/plan flip, real-money/mutating "
            "journey) or an inherent escalation (missing device/login, PII, "
            "first-time detekt): append the question to "
            "`orchestration/decision-request.md` (plain-language: problem, "
            "options, impacts, your recommendation), write "
            f"`orchestration/phase-{p}.status` = `BLOCKED`, then stop.",
            "- Batch independent gated decisions into one decision-request "
            "before stopping — never stop once per decision.",
            f"- On clean completion write `orchestration/phase-{p}.status` = "
            "`COMPLETE` and stop.",
            "- On unrecoverable failure write "
            f"`orchestration/phase-{p}.status` = `FAILED` + a one-line "
            "diagnostic (gradle log path / error summary) and stop.",
            "- Consult `references/orchestration.md` §Autopilot phase overrides "
            "for this phase's auto-decisions (e.g. Phase G opens a DRAFT PR).",
        ]
        return "\n".join(lines) + "\n"
    if role == "orchestrator":
        return (
            "\n### AUTOPILOT ORCHESTRATOR MODE\n"
            "You are the orchestrator and the single human touchpoint. Run "
            "Phases 0 and A interactively here as normal. From Phase B onward, "
            "do NOT run phases yourself — for each phase, spawn a headless "
            "worker via `scripts/run-phase-worker.sh`, then act on its status "
            "file. Follow `references/orchestration.md` (drive-loop, "
            "escalation, pre-flight, retry).\n"
        )
    return ""
```

- [ ] **Step 4: Wire the banner into the emitted report**

In `main()`, after `print(format_report(...))` (and in each early-return branch where a report/hint is printed on a kmm/ branch), also print the banner. Simplest: compute the active phase id and append. In `main()`'s normal path, change:

```python
    print(format_report(branch, folder, states))
    active = active_phase(states)
    active_id = active[0] if active else None
    banner = autopilot_banner(active_id)
    if banner:
        print(banner)
    return 0
```

(Banner is empty string when not under autopilot, so non-autopilot sessions are unaffected.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `python3 -m pytest plugins/kmm-migration-workflow/hooks/tests/test_resume_autopilot.py -q`
Expected: PASS (4 passed).

- [ ] **Step 6: Verify non-autopilot path is unchanged**

Run: `python3 -c "import os; os.environ.pop('KMM_AUTOPILOT_ROLE', None); import importlib.util,pathlib; s=importlib.util.spec_from_file_location('r', pathlib.Path('plugins/kmm-migration-workflow/hooks/resume_session.py')); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print(repr(m.autopilot_banner('B')))"`
Expected: `''`

- [ ] **Step 7: Commit**

```bash
git add plugins/kmm-migration-workflow/hooks/resume_session.py \
        plugins/kmm-migration-workflow/hooks/tests/test_resume_autopilot.py
git commit -m "feat(kmm): autopilot mode banner in resume hook (worker/orchestrator)"
```

---

### Task B3: `run-phase-worker.sh` — spawn a worker, wait, return its status

The mechanical loop unit the orchestrator calls per phase. Spawns a `claude -p` worker in a fresh tmux window, waits for the process to exit, then reads and echoes the worker's `phase-<X>.status`. A missing status file after exit (worker crashed before writing) is reported as `FAILED`.

**Files:**
- Create: `SK/scripts/run-phase-worker.sh`
- Test: `SK/scripts/tests/test_run_phase_worker.sh`

- [ ] **Step 1: Write the failing test (stubbed claude + tmux)**

Create `SK/scripts/tests/test_run_phase_worker.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
mkdir -p "$tmp/orchestration"

# stub claude: pretends to be the worker — writes a COMPLETE status then exits 0
cat > "$tmp/claude" <<STUB
#!/usr/bin/env bash
echo "COMPLETE" > "$tmp/orchestration/phase-D.status"
exit 0
STUB
chmod +x "$tmp/claude"

# stub tmux: run the command synchronously in the foreground instead of a window
cat > "$tmp/tmux" <<'STUB'
#!/usr/bin/env bash
# only support: new-window -d -P -t <s> -n <n> -- <cmd...>  and  wait-for
case "$1" in
  new-window) shift; while [[ "$1" != "--" ]]; do shift; done; shift; "$@" ;;
  *) : ;;
esac
STUB
chmod +x "$tmp/tmux"

PATH="$tmp:$PATH" ORCH_DIR="$tmp/orchestration" \
  bash "$here/../run-phase-worker.sh" D > "$tmp/out.txt"
grep -q "^COMPLETE$" "$tmp/out.txt" || { echo "FAIL: expected COMPLETE, got:"; cat "$tmp/out.txt"; exit 1; }

# crash case: claude exits non-zero without writing a status → FAILED
cat > "$tmp/claude" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
rm -f "$tmp/orchestration/phase-E.status"
PATH="$tmp:$PATH" ORCH_DIR="$tmp/orchestration" \
  bash "$here/../run-phase-worker.sh" E > "$tmp/out2.txt"
grep -q "^FAILED" "$tmp/out2.txt" || { echo "FAIL: expected FAILED on crash"; cat "$tmp/out2.txt"; exit 1; }
echo "ok"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash SK/scripts/tests/test_run_phase_worker.sh` (expand SK)
Expected: FAIL — `run-phase-worker.sh: No such file or directory`.

- [ ] **Step 3: Implement the script**

Create `SK/scripts/run-phase-worker.sh`:

```bash
#!/usr/bin/env bash
# Spawn one headless KMM-migration phase worker in a fresh tmux window, wait for
# it to exit, then echo its status (COMPLETE | BLOCKED | FAILED).
#
# Worker invocation (locked in Task B1 — adjust --max-turns to the installed CLI):
#   claude -p "<prompt>" --dangerously-skip-permissions
#
# Usage: run-phase-worker.sh <PHASE_ID>
# Env:   ORCH_DIR  = path to .../orchestration  (default: $PWD/.kmm-orch fallback)
#        TMUX_SESSION = tmux session name to create the window in (default: current)
set -euo pipefail

phase="${1:?usage: run-phase-worker.sh <PHASE_ID>}"
orch_dir="${ORCH_DIR:?ORCH_DIR must point at the orchestration/ dir}"
status_file="$orch_dir/phase-${phase}.status"
session="${TMUX_SESSION:-$(tmux display-message -p '#S' 2>/dev/null || echo kmm)}"
window="kmm-phase-${phase}"

rm -f "$status_file"

prompt="Resume this KMM migration. Per the AUTOPILOT WORKER MODE banner, run only the active phase to completion and write your orchestration status file."

# -d: don't switch focus; -P: print window info; the worker runs to completion
# then the window's command exits. We block until the window is gone.
tmux new-window -d -P -t "$session" -n "$window" -- \
  env KMM_AUTOPILOT_ROLE=worker KMM_AUTOPILOT_PHASE="$phase" \
  claude -p "$prompt" --dangerously-skip-permissions

# Wait for the worker window to disappear (process exited).
while tmux list-windows -t "$session" -F '#{window_name}' 2>/dev/null \
        | grep -qx "$window"; do
  sleep 2
done

if [[ -f "$status_file" ]]; then
  cat "$status_file"
else
  echo "FAILED: worker for phase ${phase} exited without writing ${status_file}"
fi
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash SK/scripts/tests/test_run_phase_worker.sh`
Expected: `ok`.

- [ ] **Step 5: Make executable + commit**

```bash
chmod +x SK/scripts/run-phase-worker.sh SK/scripts/tests/test_run_phase_worker.sh
git add SK/scripts/run-phase-worker.sh SK/scripts/tests/test_run_phase_worker.sh   # (expand SK)
git commit -m "feat(kmm): run-phase-worker.sh — spawn + wait + read worker status"
```

---

### Task B4: `preflight.sh` — environment gate before device/iOS phases

Checks prerequisites BEFORE a worker is spawned, so a phase never fails late on a missing device. Exits 0 (ready) or non-zero with a human-readable reason the orchestrator escalates.

**Files:**
- Create: `SK/scripts/preflight.sh`
- Test: `SK/scripts/tests/test_preflight.sh`

- [ ] **Step 1: Write the failing test**

Create `SK/scripts/tests/test_preflight.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"

# stub adb: no devices
cat > "$tmp/adb" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "devices" ]] && { echo "List of devices attached"; echo ""; }
STUB
chmod +x "$tmp/adb"

# Phase C needs no device → ready regardless
PATH="$tmp:$PATH" bash "$here/../preflight.sh" C; rc=$?
[[ $rc -eq 0 ]] || { echo "FAIL: C should be ready"; exit 1; }

# Phase B needs a device → not ready (no adb device) → non-zero + reason
set +e
PATH="$tmp:$PATH" bash "$here/../preflight.sh" B > "$tmp/b.txt" 2>&1; rc=$?
set -e
[[ $rc -ne 0 ]] || { echo "FAIL: B should be blocked with no device"; exit 1; }
grep -qi "device" "$tmp/b.txt" || { echo "FAIL: reason should mention device"; exit 1; }

# stub adb: one device present
cat > "$tmp/adb" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "devices" ]] && { echo "List of devices attached"; echo "emulator-5554	device"; }
STUB
chmod +x "$tmp/adb"
PATH="$tmp:$PATH" bash "$here/../preflight.sh" B; rc=$?
[[ $rc -eq 0 ]] || { echo "FAIL: B ready with a device"; exit 1; }
echo "ok"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash SK/scripts/tests/test_preflight.sh`
Expected: FAIL — script not found.

- [ ] **Step 3: Implement the script**

Create `SK/scripts/preflight.sh`:

```bash
#!/usr/bin/env bash
# Pre-flight environment gate for an autopilot phase. Exits 0 if the phase's
# device/iOS prerequisites are met, else non-zero with a reason on stdout that
# the orchestrator escalates to the human.
#
# Phase device/iOS needs (per design spec §5.2):
#   B  -> Android device (B.6b golden capture)
#   D  -> macOS + Xcode (iOS compile)            [no booted device required]
#   E  -> booted iOS simulator (iosSimulatorArm64Test)
#   I  -> Android device (+ optional iOS sim; + one-time manual prod login)
#   C, F, G, H -> nothing
set -euo pipefail
phase="${1:?usage: preflight.sh <PHASE_ID>}"

have_android_device() {
  command -v adb >/dev/null 2>&1 || return 1
  adb devices | awk 'NR>1 && $2=="device"{found=1} END{exit found?0:1}'
}
have_xcode() { command -v xcrun >/dev/null 2>&1; }
have_booted_sim() {
  command -v xcrun >/dev/null 2>&1 || return 1
  xcrun simctl list devices booted 2>/dev/null | grep -q "(Booted)"
}

case "$phase" in
  B)
    have_android_device || { echo "Phase B needs a connected Android device/emulator for runtime golden capture (B.6b). Connect one (adb devices shows none)."; exit 1; } ;;
  D)
    have_xcode || { echo "Phase D needs macOS + Xcode for the iOS compile checks (xcrun not found)."; exit 1; } ;;
  E)
    have_booted_sim || { echo "Phase E needs a booted iOS simulator for iosSimulatorArm64Test. Boot one (xcrun simctl) first."; exit 1; } ;;
  I)
    have_android_device || { echo "Phase I needs a connected Android device for the parity A/B loop, plus a one-time manual prod login on it. Connect a device and confirm you can log in."; exit 1; } ;;
  C|F|G|H) : ;;  # no device prerequisites
  *) echo "preflight: unknown phase '$phase'"; exit 2 ;;
esac
exit 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash SK/scripts/tests/test_preflight.sh`
Expected: `ok`.

- [ ] **Step 5: Make executable + commit**

```bash
chmod +x SK/scripts/preflight.sh SK/scripts/tests/test_preflight.sh
git add SK/scripts/preflight.sh SK/scripts/tests/test_preflight.sh   # (expand SK)
git commit -m "feat(kmm): preflight.sh — device/iOS gate before autopilot phases"
```

---

### Task B5: `kmm-autopilot.sh` — bootstrap the tmux session + launch the orchestrator

Thin bootstrap the user runs to start an autopilot migration: creates (or reuses) the tmux session, then launches the orchestrator as an interactive `claude` session with `KMM_AUTOPILOT_ROLE=orchestrator`.

**Files:**
- Create: `SK/scripts/kmm-autopilot.sh`
- Test: `SK/scripts/tests/test_kmm_autopilot.sh`

- [ ] **Step 1: Write the failing test (dry-run mode)**

Create `SK/scripts/tests/test_kmm_autopilot.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
# stub tmux: record the commands it would run
cat > "$tmp/tmux" <<STUB
#!/usr/bin/env bash
echo "tmux \$*" >> "$tmp/tmux.log"
case "\$1" in
  has-session) exit 1 ;;          # pretend session does not exist
  *) exit 0 ;;
esac
STUB
chmod +x "$tmp/tmux"

PATH="$tmp:$PATH" KMM_AUTOPILOT_DRYRUN=1 \
  bash "$here/../kmm-autopilot.sh" funds-business-logic > "$tmp/out.txt" 2>&1
grep -q "new-session" "$tmp/tmux.log" || { echo "FAIL: should create a session"; cat "$tmp/tmux.log"; exit 1; }
grep -q "kmm-funds-business-logic" "$tmp/tmux.log" || { echo "FAIL: session name from arg"; exit 1; }
grep -q "KMM_AUTOPILOT_ROLE=orchestrator" "$tmp/out.txt$tmp/tmux.log" 2>/dev/null \
  || grep -rq "KMM_AUTOPILOT_ROLE=orchestrator" "$tmp" || { echo "FAIL: orchestrator role not set"; exit 1; }
echo "ok"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash SK/scripts/tests/test_kmm_autopilot.sh`
Expected: FAIL — script not found.

- [ ] **Step 3: Implement the script**

Create `SK/scripts/kmm-autopilot.sh`:

```bash
#!/usr/bin/env bash
# Bootstrap an autopilot KMM migration: create/attach a tmux session and launch
# the orchestrator (interactive claude, role=orchestrator). The orchestrator runs
# Phases 0+A with you, then drives B->I via run-phase-worker.sh.
#
# Usage: kmm-autopilot.sh <feature>-<depth>
#   e.g. kmm-autopilot.sh funds-business-logic
# Env:  KMM_AUTOPILOT_DRYRUN=1  -> print/stub actions, don't exec claude
set -euo pipefail
suffix="${1:?usage: kmm-autopilot.sh <feature>-<depth>}"
session="kmm-${suffix}"

if ! tmux has-session -t "$session" 2>/dev/null; then
  tmux new-session -d -s "$session" -n orchestrator
fi

launch="env KMM_AUTOPILOT_ROLE=orchestrator claude"
prompt="Start the KMM migration autopilot for ${suffix}. Per the AUTOPILOT ORCHESTRATOR MODE banner, run Phases 0 and A with me, then drive B through I as headless workers."

if [[ "${KMM_AUTOPILOT_DRYRUN:-0}" == "1" ]]; then
  echo "[dryrun] would run in $session: $launch  (prompt: $prompt)"
  # still touch the session window so a dryrun is observable
  tmux send-keys -t "$session:orchestrator" "$launch" C-m 2>/dev/null || true
  exit 0
fi

# Send the launch command into the orchestrator window, then attach.
tmux send-keys -t "$session:orchestrator" "$launch '$prompt'" C-m
echo "Orchestrator launching in tmux session '$session'. Attaching..."
exec tmux attach -t "$session"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash SK/scripts/tests/test_kmm_autopilot.sh`
Expected: `ok`.

- [ ] **Step 5: Make executable + commit**

```bash
chmod +x SK/scripts/kmm-autopilot.sh SK/scripts/tests/test_kmm_autopilot.sh
git add SK/scripts/kmm-autopilot.sh SK/scripts/tests/test_kmm_autopilot.sh   # (expand SK)
git commit -m "feat(kmm): kmm-autopilot.sh — tmux bootstrap + orchestrator launch"
```

---

### Task B6: `references/orchestration.md` — the autopilot doctrine

The reference the orchestrator (and, for the overrides section, each worker) consults. Loaded on demand in autopilot mode.

**Files:**
- Create: `SK/references/orchestration.md`

- [ ] **Step 1: Write the doctrine file**

Create `SK/references/orchestration.md` with this content:

````markdown
# Autopilot orchestration (tmux headless phase pipeline)

Loaded **only in autopilot mode** (`KMM_AUTOPILOT_ROLE` set). Phases are a strict
safety pipeline (`0 → A → B → C → D → E → F → G → H → I`); there is no inter-phase
parallelism. Autopilot removes the *human-wait* between phases and the ceremony
gates — it does **not** loosen the four irreversible decision gates.

## Roles

- **Orchestrator** (`KMM_AUTOPILOT_ROLE=orchestrator`) — one interactive session,
  the single human touchpoint. Runs Phases 0 + A here as normal. From Phase B
  onward it does **not** run phases itself; it spawns a worker per phase and acts
  on the worker's status file. Holds only orchestration state (current phase,
  escalation queue, pre-flight results) → light context all session.
- **Worker** (`KMM_AUTOPILOT_ROLE=worker`, `KMM_AUTOPILOT_PHASE=<X>`) — a fresh
  headless `claude -p` session, one per phase, bootstrapped by the
  `resume_session` SessionStart hook. Runs exactly the active phase (incl. its
  blocking retro), then exits. Never advances, never waits for interactive input.
  Dispatches its own `Task` subagents for intra-phase parallelism (unchanged).

## Control plane (files, never pane-scraping)

Under `.kmm/migrations/kmm/<feature>-<depth>/orchestration/`:

| File | Writer | Meaning |
|---|---|---|
| `phase-<X>.status` | worker | `COMPLETE` \| `BLOCKED` \| `FAILED` (+ reason). Written atomically (temp + `mv`) just before exit. |
| `decision-request.md` | worker | plain-language problem + options + impacts + worker's recommendation; appended (batched) for each gated decision before a `BLOCKED` exit. |
| `decision-response.md` | orchestrator | the human's answer(s). The worker consumes then deletes it on its next start. |

The orchestrator waits on the worker's **process exit** (reliable), then reads the
status file. A worker that dies leaves state on disk → relaunch resumes via hook.

## Drive-loop (orchestrator, Phases B→I)

```
for phase in B C D E F G H I:
    bash scripts/preflight.sh <phase>        # device/iOS/login gate
        non-zero -> escalate the printed reason to the human; wait; re-check
    if phase == H: spawn review-pr --auto against the PR in its own window;
                   feed its findings to the Phase H worker
    status = bash scripts/run-phase-worker.sh <phase>
    case COMPLETE: continue
    case BLOCKED:
        read orchestration/decision-request.md
        present it to the human; collect the answer(s)
        write orchestration/decision-response.md
        relaunch: status = run-phase-worker.sh <phase>   # repeat until COMPLETE/FAILED
    case FAILED:
        ./gradlew --stop ; retry ONCE: status = run-phase-worker.sh <phase>
        still FAILED -> escalate the diagnostic to the human
```

The orchestrator never does phase work itself (the skill's "no code from the
orchestrator" rule, raised to phase level). Spawning workers and reading status
files is dispatch + read-only, which is allowed.

## Escalation classes

**Always escalate (the four irreversible classes):** dependency/library swap or
version, behavior-changing fix (migration-exception), scope/plan flip
(`migrate→hold` or new in-scope file), real-money/mutating device journey.

**Inherent escalations (physical / one-time):** missing device/simulator/login
(pre-flight), discovered PII (Phase B.6b), first-time detekt bootstrap accept
(Phase C).

**Everything else is auto-decided** with one-line logged reasoning in the phase
file's decisions log (visible on `tmux attach`): phase transitions, B-strategy,
promote-scope, re-validation scope, detekt after first time, PR-body content.

## Autopilot phase overrides (workers consult their row)

| Phase | Override |
|---|---|
| C | After first-time detekt bootstrap, auto-accept the detekt setup; first time → escalate. |
| E | Default promote-scope to **promote-only-clean** (move clean files, defer the rest). |
| F | No runtime smoke (removed); draft the heatmap skeleton only. |
| G | Open the PR as a **DRAFT**; never auto-merge, never auto-mark-ready. |
| H | Reviewer is `review-pr --auto` against the PR; resolve non-gated blockers through the workflow; proceed when clean. |
| I | Loop on ProductionDebug; the binding parity gate is the ProductionRelease final-sanity pass (I.2.8). |

## Failure / retry

Transient gradle failures (KSP incremental-cache `Number of loaded files in
snapshots differs`, daemon contention) are common (see SKILL.md Tooling
discipline). On `FAILED`, run `./gradlew --stop` and retry the phase once with a
fresh worker. A second failure escalates with the captured diagnostic. The
orchestrator never picks up the phase work itself.
````

- [ ] **Step 2: Verify it renders + has the key sections**

Run: `grep -cE "^## (Roles|Control plane|Drive-loop|Escalation classes|Autopilot phase overrides|Failure)" SK/references/orchestration.md`
Expected: 6.

- [ ] **Step 3: Commit**

```bash
git add SK/references/orchestration.md   # (expand SK)
git commit -m "docs(kmm): autopilot orchestration doctrine reference"
```

---

### Task B7: SKILL.md — autopilot trigger + worker/orchestrator contract + pointers

Wire the new mode into the skill's frontmatter trigger and body, and reconcile the body with the Group-A doc changes (F smoke removal wording in the phase table + Realistic expectations).

**Files:**
- Modify: `SK/SKILL.md`

- [ ] **Step 1: Write the failing assertion**

Run: `grep -nc "autopilot\|orchestration.md\|KMM_AUTOPILOT" SK/SKILL.md`
Expected NOW: 0 (the term "autopilot" appears for commit cadence but not the mode — verify; if the only hits are "commit-cadence (autopilot)" the mode is still absent). RED for the new mode wiring.

- [ ] **Step 2: Add the autopilot trigger to the frontmatter description**

In the YAML `description`, append one sentence so the mode is discoverable (keep within the description's existing style; do NOT summarize the workflow):
`Supports an autonomous tmux 'autopilot' mode that runs each phase in a fresh headless session — triggers on 'migrate X on autopilot', 'autonomous KMM migration', 'run the migration headless'.`

- [ ] **Step 3: Add an "Autopilot mode" section after "Phases — overview"**

Insert:

```markdown
## Autopilot mode (optional, tmux-orchestrated)

Invoked via `scripts/kmm-autopilot.sh <feature>-<depth>` (or when the user asks to
run the migration autonomously / headless / "on autopilot"). The mode is governed
by `references/orchestration.md` — load it when `KMM_AUTOPILOT_ROLE` is set.

- **Orchestrator** (interactive, the single human touchpoint): runs Phases 0 + A
  here as normal, then drives B→I by spawning one headless worker per phase via
  `scripts/run-phase-worker.sh`, handling each worker's status file. It never runs
  a phase itself from B onward.
- **Worker** (headless `claude -p`, one phase, then exits): runs exactly the active
  phase incl. its blocking retro, escalating only the four irreversible decision
  classes + the three inherent escalations through the file control plane; on
  start it consumes `orchestration/decision-response.md` if present.

The `resume_session` hook emits a mode banner (worker vs orchestrator) so behaviour
is deterministic. Non-autopilot (plain interactive) sessions are unaffected — the
banner is empty and phases run exactly as today.
```

- [ ] **Step 4: Reconcile the Phase F row + Realistic expectations with Group A**

In the phase-overview table, change the Phase F row's Purpose cell to drop the smoke:
`Validation — automated checks (build, baseline tests JVM+iOS, pre-merge integration, code-quality/iOS-surface) + heatmap draft. **No runtime smoke, no manual-QA gate.**`

In **Realistic expectations**, change "Phase F runs automated checks plus a runtime-crash smoke and the PR opens at Phase G." to:
`Phase F runs automated checks (no runtime smoke — Phase I's parity loop exercises the build) and the PR opens at Phase G.`

And in the same paragraph, where Phase I is described, ensure it reads "an in-skill autonomous parity loop (ProductionDebug iteration + a binding ProductionRelease final-sanity pass)".

- [ ] **Step 5: Run assertions to verify**

Run: `grep -nc "Autopilot mode\|orchestration.md\|run-phase-worker" SK/SKILL.md` → Expected: ≥3.
Run: `grep -n "runtime-crash smoke" SK/SKILL.md` → Expected: no matches (the only remaining "smoke" reference, if any, must not be in Phase F's description).

- [ ] **Step 6: Commit**

```bash
git add SK/SKILL.md   # (expand SK)
git commit -m "feat(kmm): wire autopilot mode into SKILL.md + reconcile Phase F/I wording"
```

---

## Group C — Ship

### Task C1: Version bump (lockstep) + README row

Per the repo's load-bearing rule, bump all four places together.

**Files:**
- Modify: `PR/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json` (plugin entry version + top-level `metadata.version`)
- Modify: `README.md` (the kmm-migration-workflow row)

- [ ] **Step 1: Read the current versions**

Run:
```bash
grep -n '"version"' plugins/kmm-migration-workflow/.claude-plugin/plugin.json
grep -nA2 'kmm-migration' .claude-plugin/marketplace.json | grep version
grep -n '"version"' .claude-plugin/marketplace.json | head -1   # top-level metadata.version
grep -n 'kmm-migration' README.md
```
Record the current `kmm-migration-workflow` version (the digest showed `1.13.0`; confirm).

- [ ] **Step 2: Bump the plugin version**

In `plugins/kmm-migration-workflow/.claude-plugin/plugin.json`, bump `version` minor (new feature): `1.13.0` → `1.14.0` (use the confirmed current value +0.1.0).

- [ ] **Step 3: Bump the marketplace entry + top-level metadata version**

In `.claude-plugin/marketplace.json`: set the `kmm-migration-workflow` plugin entry's `version` to match (`1.14.0`), and bump the top-level `metadata.version` by one patch/minor per the repo's convention (match how prior bumps moved it).

- [ ] **Step 4: Update the README row**

In `README.md`, update the kmm-migration-workflow row's version cell to `1.14.0` (and, if the row has a description/feature cell, add a brief "+ tmux autopilot mode" note — keep it terse, do not rewrite the description).

- [ ] **Step 5: Verify no version drift**

Run:
```bash
grep '"version"' plugins/kmm-migration-workflow/.claude-plugin/plugin.json
grep -A3 '"kmm-migration-workflow"' .claude-plugin/marketplace.json | grep version
grep -i 'kmm-migration-workflow' README.md
```
Expected: plugin.json version == marketplace entry version == README row version (`1.14.0`).

- [ ] **Step 6: Commit**

```bash
git add plugins/kmm-migration-workflow/.claude-plugin/plugin.json .claude-plugin/marketplace.json README.md
git commit -m "chore(kmm): bump kmm-migration-workflow 1.13.0 -> 1.14.0 (autopilot mode)"
```

---

### Task C2: Full validation + test sweep

- [ ] **Step 1: Validate the marketplace**

Run: `claude plugin validate .`
Expected: success, no errors.

- [ ] **Step 2: Run every new/changed test**

Run:
```bash
python3 -m pytest plugins/kmm-migration-workflow/hooks/tests/ -q
bash plugins/kmm-migration-workflow/skills/kmm-migration/scripts/tests/test_run_phase_worker.sh
bash plugins/kmm-migration-workflow/skills/kmm-migration/scripts/tests/test_preflight.sh
bash plugins/kmm-migration-workflow/skills/kmm-migration/scripts/tests/test_kmm_autopilot.sh
```
Expected: all pass (`ok` / `passed`).

- [ ] **Step 3: Confirm the existing tests still pass (no regressions)**

Run:
```bash
bash plugins/kmm-migration-workflow/skills/kmm-migration/scripts/tests/test_ad_capture.sh
python3 -m pytest plugins/kmm-migration-workflow/skills/kmm-migration/scripts/tests/ -q 2>/dev/null || true
```
Expected: `ok` from the bash test; existing pytest (if any) green.

- [ ] **Step 4: Grep-sweep the cross-reference invariants**

Run:
```bash
grep -rn "kmm-qa-autopilot" plugins/kmm-migration-workflow/ ; echo "expect: none"
grep -rn "F.5 smoke\|Runtime-crash smoke" plugins/kmm-migration-workflow/ ; echo "expect: none"
grep -rln "ProductionDebug" plugins/kmm-migration-workflow/skills/kmm-migration/references/phases/phase-i-qa.md ; echo "expect: present"
```
Expected: first two empty, third prints the file.

---

### Task C3: Self-review against the spec, then open the PR

- [ ] **Step 1: Spec-coverage self-check**

Re-read `docs/superpowers/specs/2026-06-07-kmm-migration-autopilot-design.md` §9 and confirm each item maps to a task: §9.1 Phase F smoke → A2; §9.2 Phase I flavors → A3; §9.3 qa-autopilot/Maestro → A1 (+ Maestro already absent, verified in C2 grep); §9.4 new layer → B2–B7; §9.5 version bump → C1. List any gap; if found, add a task and implement before the PR.

- [ ] **Step 2: Push the branch**

```bash
git push -u origin feat/kmm-autopilot-orchestration
```

- [ ] **Step 3: Open the PR**

```bash
gh pr create --title "feat(kmm): tmux autopilot mode + Phase F/I refinements" --body "$(cat <<'BODY'
Adds an optional tmux-orchestrated **autopilot** mode to the kmm-migration skill:
an interactive orchestrator runs Phases 0+A, then drives B→I as fresh headless
`claude -p` workers (one phase each) communicating via a file control plane.
Only four irreversible decision classes + three inherent escalations pause for the
human; everything else is auto-decided with logged reasoning.

Also includes the agreed skill-doc surgery:
- Phase F: runtime smoke removed (Phase I's parity loop covers runtime); F loses its device dep.
- Phase I: ProductionDebug iteration loop + binding ProductionRelease final-sanity gate (R8 false-green guard).
- Removed stale `kmm-qa-autopilot` references (Phase I is self-contained; Maestro already absent).

New: `references/orchestration.md`, `scripts/{kmm-autopilot,run-phase-worker,preflight}.sh`,
resume-hook mode banner. Version: kmm-migration-workflow 1.13.0 → 1.14.0.

Design spec: `docs/superpowers/specs/2026-06-07-kmm-migration-autopilot-design.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

- [ ] **Step 4: Report the PR URL to the user.**

---

## Self-Review (author's check against the spec)

**Spec coverage:** §9.1 → A2; §9.2 → A3; §9.3 → A1 (Maestro absence verified in C2); §9.4 (orchestration.md → B6; scripts → B3/B4/B5; resume-hook mode → B2; SKILL trigger → B7); §9.5 → C1. §5 escalation classes encoded in B2 banner + B6 doctrine. §3.1 control plane encoded in B2/B3/B6. §6 drive-loop in B6. §7 retry in B6 + drive-loop. Invocation contract (open question #1) resolved in B1 + B3. No gaps.

**Placeholder scan:** version numbers are stated as "confirm current, +0.1.0" with an exact target (1.14.0) and a verification step — not a placeholder. Flag names in B1/B3 are explicitly version-probed rather than assumed. No TODO/TBD.

**Type/name consistency:** env vars `KMM_AUTOPILOT_ROLE` / `KMM_AUTOPILOT_PHASE`, status values `COMPLETE`/`BLOCKED`/`FAILED`, files `phase-<X>.status` / `decision-request.md` / `decision-response.md`, function `autopilot_banner`, scripts `kmm-autopilot.sh` / `run-phase-worker.sh` / `preflight.sh` are used identically across B2–B7, the hook test, and orchestration.md.
