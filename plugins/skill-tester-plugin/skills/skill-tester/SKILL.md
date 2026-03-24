---
name: skill-tester
description: >
  Automated QA loop for Claude Code skills. Spins up a 3-pane tmux workflow
  (developer, consumer, orchestrator) to iteratively test, validate, and fix
  any skill until all quality checks pass. Use when developing, refining,
  or verifying a skill before release. Triggers on "skill tester", "test skill",
  "skill test loop", "validate skill", "test <skill-name>", "test my skill",
  "run skill tester", "skill dev loop", or any request to QA-test a Claude
  Code skill plugin.
---

# Skill Tester — Automated Development & Validation Loop

You are a QA orchestrator for Claude Code skills. You manage a 3-pane tmux
workflow that iteratively tests a skill against its own quality criteria until
all checks pass.

## Prerequisites

Verify before starting:
- Running inside tmux (`$TMUX` must be set)
- Inside the skills repo or user specifies the repo path
- `gh auth status` succeeds (for issue filing)
- User specifies which skill to QA

## Phase 0: Discovery & Setup

### 0a. Identify the target skill

Parse the user's request to determine which skill to QA. If ambiguous, list:

```bash
ls -d <repo>/plugins/*/skills/*/SKILL.md | sed 's|.*/plugins/||;s|/skills/.*||' | sort -u
```

Resolve paths:
- `REPO_ROOT`: The skills repo root
- `PLUGIN_DIR`: `plugins/<plugin-name>/`
- `SKILL_DIR`: `plugins/<plugin-name>/skills/<skill-name>/`
- `SKILL_MD`: `${SKILL_DIR}/SKILL.md`
- `REFS_DIR`: `${SKILL_DIR}/references/`
- `PLUGIN_JSON`: `${PLUGIN_DIR}/.claude-plugin/plugin.json`

### 0b. Extract validation checklist

Read the target skill's `SKILL.md` completely. Read every file in `references/`.

Build a **validation checklist** from these sources:
1. Find every imperative statement (MUST, NEVER, ALWAYS, mandatory, required)
2. Find every post-flight check item
3. Find every rule or directive

Split into two categories:
- **Behavioral checks**: What the consumer's output MUST exhibit
  (e.g., "functions under 20 lines", "domain language", "no comments")
- **Mechanical checks**: What the skill infrastructure MUST do
  (e.g., "prehook fires", "reference files exist", "version fields match")

Present the checklist to the user for approval. They may add or remove items.

### 0c. Generate or accept test prompts

If the user provides test prompts, use those. Otherwise, generate based on
the skill's purpose:

- **Happy path**: Straightforward request that triggers the skill
- **Edge case**: Tests boundary conditions of the skill's rules
- **Production**: Real-world scenario (ViewModel, API handler, etc.)
- **Multi-concern**: Exercises multiple rules simultaneously

Minimum: 3 prompts. Present to the user for approval.

### 0d. Set up tmux panes

```bash
# Developer pane (skill repo)
tmux split-window -h -c "<REPO_ROOT>"

# Consumer pane (clean workspace)
tmux split-window -v -c "/tmp/skill-tester-workspace"
```

Label the panes for the user:
- Left: Orchestrator (you)
- Top-right: Developer (fixes skill)
- Bottom-right: Consumer (tests skill)

## Phase 1: Mechanical Health Check

Before entering the QA loop, verify infrastructure. Run once:

1. `plugin.json` exists and has valid `name` and `version`
2. `SKILL.md` has valid frontmatter with `name` and `description`
3. Every file referenced in SKILL.md via backtick paths exists in `references/`
4. If `hooks/hooks.json` exists, verify referenced scripts exist and are executable
5. If a hook script exists, run it with `CLAUDE_PLUGIN_ROOT` set and verify valid JSON output
6. Plugin cache has the latest version

If any check fails, send fix to developer pane BEFORE entering the consumer loop.

## Phase 2: QA Loop

For each test prompt, execute this cycle:

### 2a. Launch fresh consumer

A fresh Claude session is NON-NEGOTIABLE — it forces plugin cache refresh:

```bash
# Kill existing session
tmux send-keys -t <consumer-pane> C-c
sleep 1
tmux send-keys -t <consumer-pane> "exit" Enter 2>/dev/null
sleep 2

# Clean workspace
rm -rf /tmp/skill-tester-workspace && mkdir -p /tmp/skill-tester-workspace

# Launch fresh Claude
tmux send-keys -t <consumer-pane> "cd /tmp/skill-tester-workspace && claude --dangerously-skip-permissions" Enter
```

### 2b. Send test prompt

Wait for Claude to initialize (5-8 seconds), then:

```bash
sleep 7
tmux send-keys -t <consumer-pane> "<test-prompt>" Enter
```

### 2c. Wait and capture

Poll for completion — check if the consumer has returned to idle:

```bash
# Capture output periodically
tmux capture-pane -t <consumer-pane> -p -S -100
```

Look for the Claude prompt indicator (`❯`) appearing after output. If the
output contains "Do you want to" or permission prompts, approve them.

### 2d. Validate against checklist

Read the captured output. For EACH checklist item:
- **PASS**: Output demonstrably satisfies the criterion. Cite evidence.
- **FAIL**: Output violates the criterion. Cite the specific violation.
- **N/A**: Criterion does not apply to this test prompt.

Also read the generated file(s) directly for thorough validation.

### 2e. Generate feedback (if failures)

For each FAIL, create actionable feedback:
1. **What failed**: The checklist item
2. **Evidence**: Exact text/code that violates it
3. **Root cause**: Why the skill produced this (SKILL.md wording? Missing rule? Hook issue?)
4. **Suggested fix**: Specific change to make in skill files

### 2f. Send to developer pane

Send the feedback as a prompt to the developer pane:

```bash
tmux send-keys -t <developer-pane> "<feedback-prompt>" Enter
```

The developer pane should:
1. Fix the skill files
2. Commit and push
3. Report done

### 2g. Update plugin cache

After developer pushes, sync the cache:

```bash
cp -r <REPO_ROOT>/<PLUGIN_DIR> ~/.claude/plugins/cache/punchhq-skills/<skill-name>/<version>/
# Also update marketplaces directory
cp -r <REPO_ROOT>/<PLUGIN_DIR>/* ~/.claude/plugins/marketplaces/punchhq-skills/plugins/<plugin-dir>/ 2>/dev/null
```

### 2h. Loop or advance

- All items PASS → move to next test prompt
- Any FAIL → repeat from 2a (same prompt, up to MAX_ITERATIONS=5)
- MAX_ITERATIONS reached → file GitHub issue, move to next prompt

## Phase 3: Regression Check

After all prompts pass individually, re-run the FIRST prompt to verify
fixes for later prompts didn't break earlier ones.

If regression: enter targeted fix loop for the regressed prompt.

## Phase 4: Final Report

Print a summary table:

```
## Skill QA Report: <skill-name>
Date: <YYYY-MM-DD>
Version: <start> → <end>
Iterations: <total>
Status: PASS | PARTIAL | FAIL

| # | Test Prompt | Iterations | Status |
|---|------------|------------|--------|
| 1 | <prompt>   | <n>        | PASS   |

### Issues Fixed
- <description> (v<version>)

### Issues Filed (unresolved)
- <GitHub issue URL>
```

## Phase 5: Cleanup

Ask the user: "Keep panes open or close them?"

```bash
# If close:
tmux kill-pane -t <consumer-pane>
tmux kill-pane -t <developer-pane>
```

## Key Principles

1. **The skill validates itself** — Criteria come from the skill's own
   SKILL.md and references, not external standards
2. **Fresh sessions are non-negotiable** — Consumer pane = new Claude session
   each iteration. This is how real users encounter the skill
3. **Evidence over assertion** — Every PASS/FAIL must cite specific text
4. **Minimal fixes** — One fix per cycle makes cause-and-effect traceable
5. **The user watches** — tmux panes exist for observability
6. **Regression is the enemy** — A fix that breaks a passing prompt is
   worse than no fix

## Convergence Criteria

PASS when:
- Every behavioral checklist item passes for every test prompt
- Every mechanical checklist item passes
- Regression check passes

FAIL when:
- Any prompt exceeds MAX_ITERATIONS without converging
- A mechanical defect cannot be fixed
