# Migration Retrospective — Self-Improvement Protocol

## When to trigger

Run **automatically** at these points — do NOT wait for the user to ask:
- After Phase 1 (PLAN) is approved — capture planning-phase learnings before /clear
- After Phase 3 (SHARED CODE MIGRATION) completes — capture execution-phase learnings before /clear
- After all phases complete — capture execution-phase learnings
- On any REQUIRES_APPROVAL that the user had to manually resolve

The retrospective MUST complete BEFORE the orchestrator instructs `/clear`. Context is erased on clear — if the retrospective hasn't run, all session learnings are permanently lost.

## What to scan for

### Source Material — Four Signal Types

Scan FOUR signal types in the conversation:

**Signal 1: Code/library learnings** (existing — Categories A, B, D, E)
- Scan findings.md, build errors, test failures, library discoveries
- Look for: dependency swaps that surprised, APIs that didn't work on Native, build config gotchas

**Signal 2: Steering corrections** (Category F)
- Scan for user messages containing: negation ("no", "don't", "stop", "wrong"), redirection ("instead", "use X", "do Y first"), frustration signals ("I already said", "again", "why"), and option overrides (user picking non-recommended REQUIRES_APPROVAL choice)
- For each correction found: extract the general behavioral pattern the orchestrator got wrong

**Signal 3: System observations** (Category G)
- Scan for: agent re-dispatch events (BLOCKED → re-dispatch), long gaps between user messages (indicates waiting/spinning), `/clear` events (context pressure), high tool-call counts per task (spin detection), repeated file reads by the same agent (token waste), and orchestrator self-observations about timing/efficiency
- Derive systemic fixes from patterns, not individual incidents

**Signal 4: Auto memory promotion**
- Read `~/.claude/projects/<project>/memory/MEMORY.md` (index) and all referenced topic files
- For each entry: (1) is it KMM-specific and non-obvious? (2) is it already in skill reference files? (3) does it pass the 70-point skill-worthiness gate?
- If yes to 1+3 and no to 2 → propose for promotion into skill reference files
- Deduplication is mandatory — cross-reference every memory entry against ALL existing skill files before proposing
- Common memory entries that should NOT be promoted: project-specific build commands, project-specific class names, user preferences already in CLAUDE.md

Cross-reference ALL findings against existing skill files AND against each other to avoid duplicate learnings within the same retrospective.

### Category A: Decision Framework Gaps
Scan conversation for patterns where the user had to guide a dependency/architecture choice:
- User said "use X instead" or "what about X?" for a library choice
- User corrected an approach ("no, don't do expect/actual, use multiplatform-settings")
- User asked "what makes more sense?" forcing the orchestrator to analyze options it should have proactively recommended

**Output:** New row in `references/dependency-decision-framework.md` with the library, decision, replacement, and rationale.

### Category B: Missing Guardrails
Scan for corrections to code patterns or conventions:
- "don't add Shared prefix"
- "don't use type casting"
- "keep names natural"
- Any pattern correction that applies to ALL future KMM migrations (not project-specific)

**Output:** New rule in SKILL.md Rules section.

### Category C: Process Improvements
Scan for process friction — broader than just "steps skipped or wrong order":
- Steps the orchestrator skipped that should be mandatory
- Steps that ran in wrong order
- Quality checks that should have caught issues earlier
- User having to ask for something that should be automatic
- Workflow pattern observations:
  - "Orchestrator should have batched REQUIRES_APPROVAL items at phase boundary"
  - "Phase 1 should ask dependency decisions BEFORE generating migration-guide.md entries"
  - "The orchestrator asked N questions in sequence — should batch them"
  - "Agent dispatch order was wrong — X should have run before Y"
  - "This step should be a Haiku sub-agent, not orchestrator (too simple)"
  - "Manual test checklist was too vague / too detailed / missing screens"
  - "Team composition was suboptimal — needed more/fewer agents for this module size"
  - "Tmux pane allocation was wrong — this agent should/shouldn't have had its own pane"
- **Scan for:** User saying "why didn't you...", "you should have...", "next time...", "that was unnecessary", "skip this", "do this first"

**Output:** Updated step/sequence in SKILL.md Phase sections OR `references/planning-and-execution.md`.

### Category D: Platform Gotchas
Scan for iOS/Android-specific issues discovered during migration:
- APIs that don't exist in commonMain (discovered at compile time)
- Runtime behavior differences between platforms
- Build configuration surprises

**Output:** New entry in `references/platform-api-gotchas.md` (for APIs not available on Native) or `references/kmm-architecture.md` gotchas section (for architectural/runtime gotchas).

### Category E: Library-Specific Knowledge
New information about KMM library compatibility:
- "mobilenetworkingsdk is already KMM"
- "ObjectBox doesn't support KMM"
- Version-specific features ("coroutines 1.8.0+ has Dispatchers.IO in commonMain")

**Output:** Summary row (library → decision → replacement → rationale) goes in `references/dependency-decision-framework.md`. Full before/after code examples go in `references/dependency-replacements.md`. If both are needed, update both files.

### Category F: Steering Corrections
Scan conversation for instances where the user redirected the orchestrator's behavior:
- User negation: "no", "don't", "stop", "wrong", "not what I meant"
- User redirection: "instead", "use X", "do Y first", "skip this"
- User frustration signals: "I already said", "again", "why didn't you"
- Option overrides: user picking a non-recommended option in REQUIRES_APPROVAL
- User manually doing something the orchestrator should have automated
- User overriding the orchestrator's phase/task order

**Extract the pattern, not the instance.** "User had to correct the orchestrator to check existing project usage before web searching" → rule: "always grep project first before external research."

The key difference from Category B: B is about code patterns. F is about orchestrator behavior patterns (workflow decisions, dispatch order, question sequencing, mode routing).

**Output:** New rule in SKILL.md Rules section OR updated instruction in `references/agent-protocol.md`.

### Category G: System & Performance Observations
Scan conversation and execution patterns for systemic issues about HOW the skill runs (not WHAT code it produces):
- Context bloat: conversation hit token limits, agent re-read files multiple times
- Agent spinning: agent tried >50 tool calls on same task, or same approach with minor variations
- Time sinks: phase or task took disproportionately long (identify root cause)
- Model routing mismatches: Haiku could've handled a Sonnet task, or vice versa
- Parallelism failures: tasks that could've been parallel ran sequentially
- Token waste: agent re-read the same file 4+ times, or loaded unnecessary reference files
- Team coordination gaps: agents both discovered the same issue independently, or missed a binding
- Verification pipeline observations: certain checks consistently find 0 issues (too heavyweight?)
- `/clear` timing: should have cleared earlier (context was stale), or cleared too early (lost needed context)
- Tmux observations: pane allocation suboptimal, session management issues

**Derive the systemic fix, not just the observation.** Don't just note "Phase 1 was slow" — propose "parallelize tasks 1.7-1.9 as Haiku sub-agents fired by the researcher team member."

**Output:** Updated dispatch pattern in SKILL.md OR `references/planning-and-execution.md` OR `references/agent-protocol.md` (tool-call budget adjustments, model routing changes, parallelism changes, team composition).

## Execution — Observe → Discuss → Apply

The retrospective runs in-session (before `/clear`) while full conversation context is available.

### Phase 1 — OBSERVE (autonomous)

1. Scan conversation + auto memory + findings.md for all 7 categories (A-G) using the four signal types above, across these four sources:
   1. Current conversation history
   2. `findings.md` from the current session
   3. `~/.claude/projects/<project>/memory/MEMORY.md` and its referenced topic files
   4. Orchestrator self-observations logged during execution
2. Score each finding against the Skill-Worthiness Gate
3. Group findings by risk tier:
   - **High-risk:** System/process changes (C, G) — architectural, affect execution patterns
   - **Medium-risk:** Steering corrections (F) — behavioral rules, affect orchestrator behavior
   - **Low-risk:** Code/library (A, B, D, E) — concrete patterns, well-scoped changes
4. Cross-reference against existing skill files — drop duplicates
5. Cross-reference against open GitHub issues — identify overlaps

### Phase 2 — DISCUSS (interactive with user)

Present findings by risk tier. **The retro earns its optimizations through discussion, not autonomous application.** System and process changes are architectural decisions that need human judgment.

Each finding is classified into one of 3 destinations:
- **KMM-universal** → skill reference files (shared with everyone via plugin)
- **Project-specific** → `knowledge/<project>.md` (shared with everyone on same project via plugin)
- **Ephemeral** → skip (only relevant to this session, already in findings.md or auto memory)

**For each high-risk finding (C, G):**
- What was observed (specific conversation moments, timing data, token counts)
- Why it matters (speed impact, quality impact, cost impact)
- Proposed optimization (concrete change to which skill file, which section)
- Trade-offs (what could go wrong, what this doesn't solve)
- Ask: apply / modify / skip?

**For each medium-risk finding (F):**
- What the user corrected and how many times
- The general pattern extracted (not project-specific)
- Proposed rule/instruction change (which file, exact wording)
- Ask: apply / modify / skip?

**For low-risk findings (A, B, D, E):**
- Present as a batch summary (these are lower-risk, well-scoped)
- Ask: apply all / review individually / skip?

### Phase 3 — APPLY (after user approval)

Only apply findings the user approved or modified. Using the retro-team pattern:

1. `cd ~/dev/claude-code-skills` — **Source Repo Gate** (see Consolidation Mandate)
2. Create branch: `git checkout -b retro/<module-name>-<date>`
3. Fire parallel Sonnet sub-agents (one per target file):
   - Sub-agent A: apply approved findings → `references/rules-and-guardrails.md`
   - Sub-agent B: apply approved findings → `references/platform-api-gotchas.md`
   - Sub-agent C: apply approved findings → `SKILL.md`
   - Sub-agent D: apply approved findings → `references/agent-protocol.md`
   (Only dispatch agents for files that have approved findings)
4. Collect results, verify consolidation mandate rules 1-6
5. Bump version in `plugin.json` (patch for fixes, minor for new capabilities)
6. Raise PR: `gh pr create --title "[kmm-retro] <module>: N learnings" --body "..."`
7. Self-review: `gh pr diff` → verify rules + source repo paths
8. Report summary table to user

### Summary Output

```
Retrospective complete — N findings, M approved, K applied:

| # | Category | Finding | Risk | Status | Target | Issue/PR |
|---|----------|---------|------|--------|--------|----------|
| 1 | G | Phase 1 research serial bottleneck | High | Applied | planning-and-execution.md | PR #52 |
| 2 | F | Orchestrator skipped project grep | Medium | Applied | agent-protocol.md | PR #52 |
| 3 | D | Dispatchers.IO needs explicit import | Low | Applied | platform-api-gotchas.md | PR #52 |
| 4 | G | Tmux pane overkill for 3-file module | High | Skipped | — | — |
```

## Skill-Worthiness Gate

Before adding any learning to the skill, score it:

| Criterion | Points |
|-----------|--------|
| Specific to KMM migration (not generic programming) | +30 |
| Non-obvious (would surprise a senior KMM developer) | +25 |
| Hard-won (required debugging, caused a real failure) | +25 |
| Not already covered by existing skill rules | +20 |
| Improves execution speed/cost (saves tokens, wall-clock time, or model tier) | +20 |
| User corrected the same pattern more than once in the session | +15 |
| Generic programming advice ("use error handling") | -30 |
| Already in platform-api-gotchas.md or similar reference | -20 |

**Threshold: 70 points.** Below 70 → skip or merge into an existing rule. Above 70 → add as a new entry.

The new criteria (+20 speed/cost, +15 repeat corrections) ensure that steering corrections and system observations are eligible — not just code patterns.

The goal is to keep the skill sharp, not long. Every addition must earn its place.

## Lean Output Format

Retrospective findings MUST use this structured format (not verbose prose):

```
Finding: {
  category: A|B|C|D|E|F|G,
  target_file: <which skill file should change>,
  existing_rule: <quote the existing rule to update, or "none" if new>,
  proposed_change: <1-line description of what to change>,
  rationale: <1-line why this matters>
}
```

When creating GitHub issues, group findings by target_file. Each issue should be actionable by the Improve mode — classify, find home, rewrite to absorb.

## Consolidation Mandate

### CRITICAL: Source Repo Gate (execute FIRST — before ANY file edit)

All Improve-mode edits MUST target `~/dev/claude-code-skills/` — the skill's source repository. NEVER edit files under `~/.claude/plugins/` (the read-only plugin installation — changes there are lost on updates and bypass review).

**Pre-flight checklist (mandatory before the first Edit/Write call):**
1. Resolve source path: `SOURCE=~/dev/claude-code-skills/plugins/kmm-plugin/skills/kmm-workflow`
2. Verify it exists: `ls $SOURCE/SKILL.md`
3. Create branch THERE: `cd ~/dev/claude-code-skills && git checkout -b <branch>`
4. ALL subsequent Read/Edit/Write calls use absolute paths starting with `~/dev/claude-code-skills/`

**Self-check:** If any file path in an Edit/Write call contains `.claude/plugins` → STOP immediately. Wrong location. This is the #1 recurring Improve-mode failure.

### Consolidation Rules

1. **NEVER append** — find the existing rule and REWRITE it to absorb the learning.
2. **Measure file growth:** net >10 lines after applying learnings → consolidate further. Sharper, not longer.
3. **One source of truth:** learning goes in reference doc, not SKILL.md. SKILL.md stays lean.
4. **Generalization mandatory:** strip project-specific names. Extract reusable patterns.
5. **Bump semver:** patch for learnings/fixes, minor for new capabilities, major for breaking changes. Do NOT update `description` in `plugin.json` or SKILL.md frontmatter.
6. **Self-review before presenting PR:** `gh pr diff` → verify rules 1–5 + source repo paths. Fix violations before presenting.

## Improve Mode — Review & Batch

Since the retrospective now creates PRs directly (with full conversation context), Improve mode becomes a lightweight review role:

1. **List open retro PRs:** `gh pr list --label "skill:kmm-workflow"`
2. **List orphaned issues:** `gh issue list --label "skill:kmm-workflow" --state open` — issues from retros that failed to create PRs
3. **Batch-consolidate orphans:** If orphaned issues exist, create one batch PR consolidating them
4. **Cross-check:** Are any retro PRs redundant or conflicting? Suggest merges
5. **Review merged PRs:** Since last improve — any post-merge issues or regressions?

No team needed. Orchestrator handles this alone.

## Issue format

Title: `[kmm-retro] <project-name>: <N> learnings from migration`

Body contains for each learning:
- **File to modify:** exact path
- **Section:** where in the file
- **Content to add:** the actual markdown/text to insert (copy-pasteable)
- **Rationale:** why this was learned (what went wrong without it)

Labels: `skill:kmm-workflow`, `type:self-improvement`, `session:<date>`

- **Always create retrospective issues on the skill's own repo** (detect via `gh repo view --json nameWithOwner`), NOT on the app repo being migrated. The learnings are about the skill itself, not the app.

## Generalization rule (mandatory)

Every learning MUST be generalized before capturing. The skill's reference files are project-agnostic — they must be useful for ANY KMM migration, not just the current project.

**Before writing any learning, strip:**
- Project-specific class/interface names → replace with generic examples (e.g., `MyUseCase` not `IGetEstimatedMarginUseCase`)
- Branch names, repo names, artifact names → describe the pattern (e.g., "check if a KMM branch exists" not "merge `feature/xyz-kmm`")
- API endpoints, server names, product names → describe the category (e.g., "backend server" not "Heimdall")
- Gameplan/phase-specific context → extract the reusable principle

**Test:** Would a developer on a completely different Android→KMM project find this learning useful as-is? If they'd need to mentally replace project names to understand it, it's not generalized enough.

**For external SDK dependencies:** When capturing a learning about an SDK's KMM availability, do NOT record the specific SDK. Instead, record the **process improvement** — e.g., "always ask the user if a KMM version exists for external SDK deps before building Android bridge adapters."

## What NOT to capture

- Project-specific decisions (base URLs, artifact names, branch names, class names)
- One-off bugs that were fixed during the session
- User preferences that are already in CLAUDE.md (like "no type casting")
- Anything already in the skill's reference files
- Phase-specific or gameplan-specific details that only apply to the current session
