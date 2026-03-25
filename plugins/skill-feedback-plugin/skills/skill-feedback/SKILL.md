---
name: skill-feedback
description: End-of-session skill auditor that reviews all skills used in the current Claude Code session and raises GitHub Issues with actionable improvement feedback for each skill. Use whenever the user says "skill feedback", "review skills", "session feedback", "how did skills perform", "skill audit", "improve my skills", "rate the skills", "skill review", "what worked what didn't", "feedback loop", or any request to evaluate skill quality after a work session. Also triggers on "end of session review", "retrospective", "skill retro", or "raise skill issues". This skill reads the session log (populated by a PostToolUse hook), interactively captures developer experience per skill, then creates GitHub Issues on the skill marketplace repo with structured feedback, improvement suggestions, and trend analysis from past issues.
---

# Skill Feedback

An end-of-session auditor that closes the feedback loop on your skill ecosystem. Detects which skills were invoked during the session, captures your developer experience interactively, and raises structured GitHub Issues per skill — complete with trend analysis from prior issues.

## Prerequisites

### 1. PostToolUse hook (bundled)

This plugin includes a PostToolUse hook that automatically logs every skill invocation to `~/.skill-session-log.jsonl`. The hook is installed automatically when you install the plugin from the marketplace — no manual setup required.

### 2. GitHub CLI (`gh`)

The `gh` CLI must be installed and authenticated:

```bash
gh auth status   # verify authentication
```

### 3. Repository configuration

Before first use, set the target repo for issues. Read `references/github-config.md` and follow its instructions. This only needs to be done once — the repo slug is stored in `~/.skill-feedback-config.json`.

## When to use

- End of a Claude Code work session — reflect on which skills helped and which need improvement
- After a frustrating experience with a skill — capture the pain while it's fresh
- Periodic skill ecosystem health check
- Before iterating on a skill — check existing GitHub Issues for prior feedback

## Two-phase workflow

Execute these phases in order. Read the referenced file for each phase BEFORE generating output.

### Phase 0: Pre-flight checks

1. Verify `gh auth status` succeeds. If not, tell the developer and stop.
2. Read repo config from `~/.skill-feedback-config.json`. If missing, ask the developer for the repo name (format: `owner/repo`) and create it:
   ```bash
   echo '{"repo": "<owner>/<repo>"}' > ~/.skill-feedback-config.json
   ```
3. Check if `~/.skill-session-log.jsonl` exists and has data.
   - If empty/missing: **fall back to conversation context analysis.** Scan the current conversation for:
     - `<command-name>` tags (indicate skill invocations)
     - `/plugin-name:skill-name` patterns in user messages
     - `system-reminder` tags mentioning skill names or prehook content
     - Any tool calls to the `Skill` tool
   - Build the skill list from what you find in context. Do NOT ask the developer to manually list skills — extract from context first, then confirm.
4. Run the log pruner to enforce the 7-day rolling window. The prune script is located at `../../scripts/prune-log.sh` relative to this SKILL.md (i.e., the plugin's `scripts/` directory):
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/scripts/prune-log.sh"
   ```
5. Ensure required labels exist on the repo:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-labels.sh"
   ```

### Phase 1: Discovery & experience capture

Read `references/phase1-discovery.md` and follow its instructions.

This phase:
- Parses the session log and groups invocations by skill
- Presents the discovered skills with invocation counts and summaries
- For each skill, asks four targeted experience questions
- Asks about skills that should have triggered but didn't
- Collects all responses before moving to Phase 2

### Phase 2: GitHub Issue creation

Read `references/phase2-feedback.md` and follow its instructions.

This phase:
- Creates a GitHub Issue for each skill with actionable feedback (rating < 5 or friction/missing capabilities reported)
- Applies labels: `skill:<name>`, `priority:<P0|P1|P2>`, `type:<category>`, `session:<date>`
- Cross-references past issues for trend analysis (read `references/trend-analyzer.md`)
- Skills rated ⭐⭐⭐⭐⭐ with zero issues are simply skipped — no noise

## Key principles

1. **Developer experience is the signal** — Logs tell you what ran; only the developer knows what worked. The interactive phase is the soul of this skill.
2. **Actionable over generic** — Every issue should point to a specific SKILL.md section, a missing guardrail, or a concrete capability gap.
3. **Trends via GitHub** — Use label queries and issue cross-references to surface recurring problems. No local state needed.
4. **Honest and direct** — The goal is to make skills better. Be specific about what's broken.
5. **Respect the developer's time** — Phase 1 questions should be quick. Four targeted questions per skill, move on.
6. **Don't create noise** — Only create issues when there's real feedback. Perfect skills get skipped.
